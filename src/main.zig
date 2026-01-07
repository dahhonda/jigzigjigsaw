// 標準ライブラリとかのimport
const std = @import("std");
const builtin = @import("builtin");

// jokのimport
const jok = @import("jok");
const j2d = jok.j2d;
const physfs = jok.physfs;

var rng: std.Random.DefaultPrng = undefined; // 乱数生成器
var batchpool: j2d.BatchPool(64, false) = undefined; // 描画を高速化するのに使うっぽい
var sheet: *j2d.SpriteSheet = undefined; // スプライトシート。使う画像をあらかじめ読み込んでおくのに使うっぽい
var scene: *j2d.Scene = undefined; // 描画先
var difPos: jok.Point = jok.Point{ .x = 0, .y = 0}; // ドラッグ時のズレ

// ジグソーパズルの正解画像
const JigsawPicture = struct {
    name: [*:0]const u8, //  ファイル名。 [*:0]const u8 はC言語の文字列のようにヌル終端する文字列を表す型らしい？
    rows: u32, // 何行に分割されるか
    cols: u32, // 何列に分割されるか
    piece_width: u32, // ピースの横幅
    piece_height: u32, // ピースの縦幅
};
const pictures = [_]JigsawPicture{
    .{
        .name = "images/spotch_onboarding",
        .rows = 5,
        .cols = 5,
        .piece_width = 144,
        .piece_height = 128,
    },
};

// パズルのピース
const Piece = struct {
    picture: *j2d.Scene.Object, // *で始まる型はC言語でもおなじみのポインタ。ただし、nullにはできない
    current_pos: jok.Point,
    correct_pos: jok.Point,
    is_correct: bool,
};

// ゲームの進行状況
const GamePhase = enum {
    initial,
    playing,
    completed,
};

// ゲームの状態
const GameState = struct {
    phase: GamePhase,
    picture: JigsawPicture,
    pieces: []Piece, // []で始まる型は配列？ Goにもあるようなスライス型かも
    dragging_piece_index: ?usize, // ?で始まる型はオプショナル。nullを代入できる
};
var state = GameState{
    .phase = .initial,
    .picture = undefined, // init関数で初期化するからここではundefined
    .pieces = undefined, // init関数で初期化するからここではundefined
    .dragging_piece_index = null,
};

pub fn init(ctx: jok.Context) !void {
    std.log.info("game init", .{});
    try ctx.window().setTitle("じぐじぐじぐそー: クリックでゲームを開始します");

    if (!builtin.cpu.arch.isWasm()) {
        try physfs.mount("assets", "", true);
    }

    batchpool = try @TypeOf(batchpool).init(ctx);
    scene = try j2d.Scene.create(ctx.allocator());

    // 用意されているパズル画像からランダムなものを選ぶ
    rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const puzzle_pic = pictures[rng.random().uintLessThan(usize, pictures.len)];

    // 各ピースのスプライトから2Dオブジェクトを作り、正解の位置に移動する
    const margin: u32 = 64;
    try loadPieces(ctx, puzzle_pic, margin);

    // パズル画像のサイズに合わせてウィンドウサイズを変更
    const window = ctx.window();
    try window.setSize(.{
        .width = margin * 2 + puzzle_pic.piece_width * puzzle_pic.cols,
        .height = margin * 2 + puzzle_pic.piece_height * puzzle_pic.rows,
    });
}

fn loadPieces(
    ctx: jok.Context,
    puzzle_pic: JigsawPicture,
    margin: u32,
) !void { // 戻り値の前に ! が付いているのは、エラーを返す可能性がある関数

    // Zigでは、メモリの確保と解放はAllocatorという型のオブジェクトを使って手動で行わないといけない。GCは無い。
    // jokでは、ctx引数から取得したAllocatorを使っとけばよさそう
    state.pieces = try ctx.allocator().alloc(Piece, puzzle_pic.rows * puzzle_pic.cols);
    state.picture = puzzle_pic;

    // 指定ディレクトリ内のピース画像を読み込んでスプライトシートにする。
    // 少し上でも出てきたが、tryはエラーが返ってきたらそのエラーをすぐreturnするシンタックスシュガー。
    // エラーを返す可能性がある関数を呼び出すときは、tryなり何なりでエラー処理しないとコンパイルエラーになる
    sheet = try j2d.SpriteSheet.fromPicturesInDir(ctx, puzzle_pic.name, 2560.0, 1920.0, .{});

    for (0..puzzle_pic.rows) |r| {
        for (0..puzzle_pic.cols) |c| {
            // ピースの正解の位置を計算
            const pos = jok.Point{
                // 初見では @ が何か特別な構文に見えるけど、Zigのビルトイン関数は全て @ で始まる名前をしているというだけ。
                // （ユーザは @ で始まる名前の関数を定義できない）
                .x = @floatFromInt(margin + c * puzzle_pic.piece_width),
                .y = @floatFromInt(margin + r * puzzle_pic.piece_height),
            };

            // r行目,c列目のピースの画像をスプライトシートから取得する。
            // ここのallocPrintの呼び出しは、C言語でいうsprintf("r%02d_c%02d", r, c)みたいな感じ
            const filename = try std.fmt.allocPrint(ctx.allocator(), "r{d:0>2}_c{d:0>2}", .{ r, c });
            // 確保したメモリをその関数内で確実に解放したいなら、Goと同じようにdeferを使える
            defer ctx.allocator().free(filename);
            const obj = try j2d.Scene.Object.create(ctx.allocator(), .{
                .sprite = sheet.getSpriteByName(filename),
                .render_opt = .{ .pos = pos },
            }, null);

            // ピースの画像や位置などを設定
            const piece = Piece{
                .picture = obj,
                .current_pos = pos,
                .correct_pos = pos,
                .is_correct = false,
            };
            const idx = r * puzzle_pic.cols + c;
            state.pieces[idx] = piece;

            try scene.root.addChild(piece.picture);
        }
    }
}

pub fn event(ctx: jok.Context, e: jok.Event) !void {
    switch (state.phase) {
        .initial, .completed => {
            switch (e) {
                .mouse_button_down => {
                    shufflePieces(ctx);
                    state.phase = .playing;
                    try ctx.window().setTitle("じぐじぐじぐそー: ピースをドラッグしてパズルを完成させよう！");
                },
                else => {},
            }
        },
        .playing => {
            switch (e) {
                .mouse_button_down => |m| {
                    if (state.dragging_piece_index == null) {
                        if (findPieceIndexAt(m.pos)) |index| {
                            state.dragging_piece_index = index;
                            difPos = jok.Point{
                                .x = m.pos.x - state.pieces[index].current_pos.x,
                                .y = m.pos.y - state.pieces[index].current_pos.y,
                            };
                            movePieceTo(index, m.pos);

                            // ドラッグ中のピースは一番上に描画されるようにする
                            state.pieces[index].picture.removeSelf();
                            try scene.root.addChild(state.pieces[index].picture);
                        }
                    }
                },
                .mouse_motion => |m| {
                    if (state.dragging_piece_index) |index| {
                        movePieceTo(index, m.pos);
                    }
                },
                .mouse_button_up => {
                    if (state.dragging_piece_index) |index| {
                        // ピースを放した時の位置が正解の位置から一定距離以内なら、
                        // 正解の位置に移動させてそれ以上動かせないようにする。
                        var piece = state.pieces[index];
                        if (piece.current_pos.distance(piece.correct_pos) <= 16) {
                            state.pieces[index].current_pos = piece.correct_pos;
                            state.pieces[index].is_correct = true;
                        }

                        const remain = getIncorrectPieceCount();
                        if (remain == 0) {
                            // 残りピース0枚なら完成
                            try ctx.window().setTitle("じぐじぐじぐそー: 完成おめでとう！");
                            state.phase = .completed;
                        } else {
                            // 残りのピース数をタイトルに表示
                            const title = try std.fmt.allocPrint(ctx.allocator(), "じぐじぐじぐそー: 完成まで残り {d} 枚！", .{remain});
                            defer ctx.allocator().free(title);
                            const titleZ = try ctx.allocator().dupeZ(u8, title);
                            defer ctx.allocator().free(titleZ);
                            try ctx.window().setTitle(titleZ);
                        }

                        state.dragging_piece_index = null;
                    }
                },
                else => {},
            }
        },
    }
}

fn shufflePieces(ctx: jok.Context) void {
    for (0..state.pieces.len) |i| {
        state.pieces[i].current_pos = jok.Point{
            .x = @floatFromInt(rng.random().intRangeAtMost(u32, 0, ctx.window().getSize().width - state.picture.piece_width)),
            .y = @floatFromInt(rng.random().intRangeAtMost(u32, 0, ctx.window().getSize().height - state.picture.piece_height)),
        };
        state.pieces[i].is_correct = false;
    }
}

fn findPieceIndexAt(pos: jok.Point) ?usize {
    var i = state.pieces.len;
    while (i > 0) {
        i -= 1;
        // すでに正しい位置にあるピースは移動対象外
        if (state.pieces[i].is_correct) {
            continue;
        }
        var rect = jok.Rectangle{
            .x = state.pieces[i].current_pos.x,
            .y = state.pieces[i].current_pos.y,
            .width = @floatFromInt(state.picture.piece_width),
            .height = @floatFromInt(state.picture.piece_height),
        };
        if (rect.containsPoint(pos)) {
            return i;
        }
    }
    return null;
}

fn movePieceTo(piece_index: usize, pos: jok.Point) void {
    state.pieces[piece_index].current_pos = .{
        .x = pos.x - difPos.x,
        .y = pos.y - difPos.y,
    };
}

fn getIncorrectPieceCount() u32 {
    var count: u32 = 0;
    for (state.pieces) |p| {
        if (!p.is_correct) {
            count += 1;
        }
    }
    return count;
}

pub fn update(ctx: jok.Context) !void {
    _ = ctx;
}

pub fn draw(ctx: jok.Context) !void {
    try ctx.renderer().clear(.rgb(128, 128, 128));
    var b = try batchpool.new(.{ .depth_sort = .back_to_forth });
    defer b.submit();

    // もとのピースの配置が分かるようにグリッドを表示
    for (state.pieces) |p| {
        const rect = jok.Rectangle{
            .x = p.correct_pos.x,
            .y = p.correct_pos.y,
            .width = @floatFromInt(state.picture.piece_width),
            .height = @floatFromInt(state.picture.piece_height),
        };
        const color = jok.Color{ .r = 240, .g = 240, .b = 240 };
        try b.rect(rect, color, .{});
    }

    // ピースの描画
    for (state.pieces) |p| {
        var tint_color = jok.Color.white;
        if (state.phase != .completed and p.is_correct) {
            // 正解位置にあるピースは黄色っぽくする
            tint_color = .{ .a = 128, .r = 255, .g = 255, .b = 0 };
        }
        p.picture.setRenderOptions(.{
            .pos = p.current_pos,
            .tint_color = tint_color,
        });
    }
    try b.scene(scene);
}

pub fn quit(ctx: jok.Context) void {
    sheet.destroy();
    batchpool.deinit();
    scene.destroy(true);
    ctx.allocator().free(state.pieces);
}
