// 標準ライブラリとかのimport
const std = @import("std");
const builtin = @import("builtin");

// jokのimport
const jok = @import("jok");
const j2d = jok.j2d;
const physfs = jok.physfs;

var rng: std.Random.DefaultPrng = undefined; // 乱数生成器
var sheet: *j2d.SpriteSheet = undefined; // スプライト。使う画像をあらかじめ読み込んでおく
var batchpool: j2d.BatchPool(64, false) = undefined; // 描画を高速化するのに使うっぽい
var scene: *j2d.Scene = undefined; // 描画先

// ジグソーパズルとして分割する画像。
// 画像を追加するときはここを修正する。
const JigsawPicture = struct {
    name: [*:0]const u8,
    rows: u32,
    cols: u32,
    piece_width: u32,
    piece_height: u32,
};
const pictures = [_]JigsawPicture{
    .{
        .name = "images/programming_master",
        .rows = 8,
        .cols = 8,
        .piece_width = 128,
        .piece_height = 70,
    },
};

// パズルのピース
const Piece = struct {
    picture: *j2d.Scene.Object,
    current_pos: jok.Point,
    correct_pos: jok.Point,
};

// ゲームの状態
const GamePhase = enum {
    initial,
    playing,
};
const GameState = struct {
    phase: GamePhase,
    picture: JigsawPicture,
    pieces: []Piece,
    dragging_piece_index: ?usize,
};
var state = GameState{
    .phase = .initial,
    .picture = undefined,
    .pieces = &[_]Piece{},
    .dragging_piece_index = null,
};

pub fn init(ctx: jok.Context) !void {
    std.log.info("game init", .{});
    try ctx.window().setTitle("じぐじぐじぐそー: クリックでゲームを開始します");

    if (!builtin.cpu.arch.isWasm()) {
        try physfs.mount("assets", "", true);
    }

    // パズル画像からランダムなものを読み込む
    rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const puzzle_pic = pictures[rng.random().uintLessThan(usize, pictures.len)];
    sheet = try j2d.SpriteSheet.fromPicturesInDir(
        ctx,
        puzzle_pic.name,
        2560.0,
        1920.0,
        .{},
    );
    state.picture = puzzle_pic;

    batchpool = try @TypeOf(batchpool).init(ctx);
    scene = try j2d.Scene.create(ctx.allocator());

    const margin: u32 = 64;

    // 各ピースのスプライトから2Dオブジェクトを作り、正解の位置に移動する。
    state.pieces = try ctx.allocator().alloc(Piece, puzzle_pic.rows * puzzle_pic.cols);
    var r: u32 = 0;
    while (r < puzzle_pic.rows) : (r += 1) {
        var c: u32 = 0;
        while (c < puzzle_pic.cols) : (c += 1) {
            const filename = try std.fmt.allocPrint(ctx.allocator(), "r{d:0>2}_c{d:0>2}", .{ r, c });
            defer ctx.allocator().free(filename);
            const pos = jok.Point{
                .x = @floatFromInt(margin + c * puzzle_pic.piece_width),
                .y = @floatFromInt(margin + r * puzzle_pic.piece_height),
            };
            const obj = try j2d.Scene.Object.create(ctx.allocator(), .{
                .sprite = sheet.getSpriteByName(filename).?,
                .render_opt = .{ .pos = pos },
            }, null);
            const piece = Piece{
                .picture = obj,
                .current_pos = pos,
                .correct_pos = pos,
            };
            const idx = r * puzzle_pic.cols + c;
            state.pieces[idx] = piece;
            try scene.root.addChild(piece.picture);
        }
    }

    // パズル画像のサイズに合わせてウィンドウサイズを変更
    const window = ctx.window();
    try window.setSize(.{
        .width = margin * 2 + puzzle_pic.piece_width * puzzle_pic.cols,
        .height = margin * 2 + puzzle_pic.piece_height * puzzle_pic.rows,
    });
}

pub fn event(ctx: jok.Context, e: jok.Event) !void {
    switch (state.phase) {
        .initial => {
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
                            movePieceCenterTo(index, m.pos);

                            // ドラッグ中のピースは一番上に描画されるようにする
                            state.pieces[index].picture.removeSelf();
                            try scene.root.addChild(state.pieces[index].picture);
                        }
                    }
                },
                .mouse_motion => |m| {
                    if (state.dragging_piece_index) |index| {
                        movePieceCenterTo(index, m.pos);
                    }
                },
                .mouse_button_up => {
                    if (state.dragging_piece_index != null) {
                        state.dragging_piece_index = null;
                    }
                },
                else => {},
            }
        },
    }
}

fn shufflePieces(ctx: jok.Context) void {
    var i: u32 = 0;
    while (i < state.pieces.len) : (i += 1) {
        state.pieces[i].current_pos = jok.Point{
            .x = @floatFromInt(rng.random().intRangeAtMost(u32, 0, ctx.window().getSize().width - state.picture.piece_width)),
            .y = @floatFromInt(rng.random().intRangeAtMost(u32, 0, ctx.window().getSize().height - state.picture.piece_height)),
        };
    }
}

fn findPieceIndexAt(pos: jok.Point) ?usize {
    var i = state.pieces.len;
    while (i > 0) {
        i -= 1;
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

fn movePieceCenterTo(piece_index: usize, pos: jok.Point) void {
    state.pieces[piece_index].current_pos = .{
        .x = pos.x - @as(f32, @floatFromInt(state.picture.piece_width)) / 2.0,
        .y = pos.y - @as(f32, @floatFromInt(state.picture.piece_height)) / 2.0,
    };
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
        p.picture.setRenderOptions(.{
            .pos = p.current_pos,
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
