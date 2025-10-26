const std = @import("std");

const Action = enum(i8) {
    LightHit = -3,
    MediumHit = -6,
    HardHit = -9,
    Draw = -15,
    Punch = 2,
    Bend = 7,
    Upset = 13,
    Shrink = 16,

    fn max() u8 {
        comptime var max_value: u8 = 0;

        inline for (std.meta.fields(Action)) |action| {
            if (@abs(action.value) > max_value) {
                max_value = @abs(action.value);
            }
        }

        return max_value;
    }

    fn anyHit() []const Action {
        return &.{ .LightHit, .MediumHit, .HardHit };
    }

    fn anyAction() []const Action {
        return &.{ .LightHit, .MediumHit, .HardHit, .Draw, .Punch, .Bend, .Upset, .Shrink };
    }

    pub fn format(self: Action, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const colour_code: u8 = switch (self) {
            .LightHit => 14,
            .MediumHit => 27,
            .HardHit => 18,
            .Draw => 56,
            .Punch => 10,
            .Bend => 11,
            .Upset => 166,
            .Shrink => 1,
        };

        return writer.print("\x1b[38;5;{}m{s}\x1b[0m", .{ colour_code, @tagName(self) });
    }
};

fn solveForTarget(allocator: std.mem.Allocator, target_value: i32) !std.ArrayList(Action) {
    const limit = @as(u32, @abs(target_value)) + Action.max() * 3;

    const State = struct {
        position: i32,
        actions_taken: std.ArrayList(Action),
    };

    var queue = std.ArrayList(State){};
    var visited: std.AutoHashMap(i32, void) = .init(allocator);

    defer {
        for (queue.items) |*state| {
            state.actions_taken.deinit(allocator);
        }
        queue.deinit(allocator);
        visited.deinit();
    }

    try queue.append(allocator, State{
        .position = 0,
        .actions_taken = .empty,
    });
    try visited.putNoClobber(0, {});

    while (queue.items.len > 0) {
        var current_state = queue.orderedRemove(0);
        defer current_state.actions_taken.deinit(allocator);

        inline for (std.meta.fields(Action)) |action| {
            const next_position = current_state.position + action.value;
            if (next_position == target_value) {
                var solution = try current_state.actions_taken.clone(allocator);
                errdefer solution.deinit(allocator);
                try solution.append(allocator, @enumFromInt(action.value));
                return solution;
            }

            if (@abs(next_position) < limit and !visited.contains(next_position)) {
                try visited.putNoClobber(next_position, {});
                var new_actions = try current_state.actions_taken.clone(allocator);
                errdefer new_actions.deinit(allocator);
                try new_actions.append(allocator, @enumFromInt(action.value));

                try queue.append(allocator, State{
                    .position = next_position,
                    .actions_taken = new_actions,
                });
            }
        }
    }

    return error.NoSolution;
}

const RuleVariations = struct {
    variations: std.ArrayList(std.ArrayList(Action)),

    pub const empty: RuleVariations = .{
        .variations = .empty,
    };

    fn appendSingle(self: *RuleVariations, allocator: std.mem.Allocator, action: Action) !void {
        if (self.variations.items.len == 0) {
            try self.variations.append(allocator, std.ArrayList(Action){});
        }

        for (self.variations.items) |*variation| {
            try variation.append(allocator, action);
        }
    }

    fn appendMany(self: *RuleVariations, allocator: std.mem.Allocator, actions: []const Action) !void {
        if (self.variations.items.len == 0) {
            try self.variations.append(allocator, std.ArrayList(Action){});
        }

        var new_variations: RuleVariations = .empty;
        errdefer new_variations.deinit(allocator);

        for (self.variations.items) |variation| {
            for (actions) |action| {
                var new_variation = try variation.clone(allocator);
                errdefer new_variation.deinit(allocator);
                try new_variation.append(allocator, action);
                try new_variations.variations.append(allocator, new_variation);
            }
        }

        self.deinit(allocator);
        self.* = new_variations;
    }

    fn clone(self: RuleVariations, allocator: std.mem.Allocator) !RuleVariations {
        var result: RuleVariations = .empty;
        errdefer result.deinit(allocator);

        try result.variations.ensureTotalCapacity(allocator, self.variations.items.len);
        for (self.variations.items) |variation| {
            var cloned_variation = try variation.clone(allocator);
            errdefer cloned_variation.deinit(allocator);
            result.variations.appendAssumeCapacity(cloned_variation);
        }

        return result;
    }

    fn combine(self: *RuleVariations, allocator: std.mem.Allocator, other: *const RuleVariations) !void {
        try self.variations.ensureTotalCapacity(allocator, self.variations.items.len + other.variations.items.len);
        for (other.variations.items) |variation| {
            self.variations.appendAssumeCapacity(try variation.clone(allocator));
        }
    }

    fn deinit(self: *RuleVariations, allocator: std.mem.Allocator) void {
        for (self.variations.items) |*variation| {
            variation.deinit(allocator);
        }
        self.variations.deinit(allocator);
    }
};

const RuleAction = union(enum) {
    action: Action,
    any_hit: void,
    any_action: void,

    fn append_to_variations(self: RuleAction, allocator: std.mem.Allocator, variations: *RuleVariations) !void {
        switch (self) {
            .action => |a| {
                try variations.appendSingle(allocator, a);
            },
            .any_hit => {
                const any_hit = comptime Action.anyHit();
                try variations.appendMany(allocator, any_hit);
            },
            .any_action => {
                const any_action = comptime Action.anyAction();
                try variations.appendMany(allocator, any_action);
            },
        }
    }
};

const Rule = union(enum) {
    rule_1: struct {
        last: RuleAction,
    },

    rule_2: struct {
        second_last: RuleAction,
        last: RuleAction,
    },

    rule_3: struct {
        third_last: RuleAction,
        second_last: RuleAction,
        last: RuleAction,
    },

    rule_3_either_2: struct {
        before_last_1: RuleAction,
        before_last_2: RuleAction,
        last: RuleAction,
    },

    rule_2_either_1: struct {
        not_last: RuleAction,
        last: RuleAction,
    },

    fn getVariations(self: Rule, allocator: std.mem.Allocator) !RuleVariations {
        var variations: RuleVariations = .empty;
        errdefer {
            variations.deinit(allocator);
        }

        switch (self) {
            .rule_1 => |r| {
                try r.last.append_to_variations(allocator, &variations);
            },

            .rule_2 => |r| {
                try r.second_last.append_to_variations(allocator, &variations);
                try r.last.append_to_variations(allocator, &variations);
            },

            .rule_3 => |r| {
                try r.third_last.append_to_variations(allocator, &variations);
                try r.second_last.append_to_variations(allocator, &variations);
                try r.last.append_to_variations(allocator, &variations);
            },

            .rule_3_either_2 => |r| {
                var second_branch = try variations.clone(allocator);
                defer second_branch.deinit(allocator);

                try r.before_last_1.append_to_variations(allocator, &variations);
                try r.before_last_2.append_to_variations(allocator, &variations);
                try r.last.append_to_variations(allocator, &variations);

                try r.before_last_2.append_to_variations(allocator, &second_branch);
                try r.before_last_1.append_to_variations(allocator, &second_branch);
                try r.last.append_to_variations(allocator, &second_branch);

                try variations.combine(allocator, &second_branch);
            },

            .rule_2_either_1 => |r| {
                const anyAction = comptime RuleAction{ .any_action = {} };

                var second_branch = try variations.clone(allocator);
                defer second_branch.deinit(allocator);

                try r.not_last.append_to_variations(allocator, &variations);
                try anyAction.append_to_variations(allocator, &variations);
                try r.last.append_to_variations(allocator, &variations);

                try anyAction.append_to_variations(allocator, &second_branch);
                try r.not_last.append_to_variations(allocator, &second_branch);
                try r.last.append_to_variations(allocator, &second_branch);

                try variations.combine(allocator, &second_branch);
            },
        }

        return variations;
    }
};

fn sum(actions: []const Action) i32 {
    var total: i32 = 0;
    for (actions) |action| {
        total += @intFromEnum(action);
    }
    return total;
}

fn solve(allocator: std.mem.Allocator, initial_value: i32, rule: Rule) !std.ArrayList(Action) {
    var solutions: std.ArrayList(std.ArrayList(Action)) = .empty;
    defer {
        for (solutions.items) |*solution| {
            solution.deinit(allocator);
        }
        solutions.deinit(allocator);
    }

    var variations = try rule.getVariations(allocator);
    defer variations.deinit(allocator);

    for (variations.variations.items) |variation| {
        const target_value = initial_value - sum(variation.items);
        var result = solveForTarget(allocator, target_value) catch |err| switch (err) {
            error.NoSolution => continue,
            else => return err,
        };
        errdefer result.deinit(allocator);

        try result.appendSlice(allocator, variation.items);
        try solutions.append(allocator, result);
    }

    var best_solution: ?usize = null;
    for (0.., solutions.items) |index, solution| {
        if (best_solution == null or solution.items.len < solutions.items[best_solution.?].items.len) {
            best_solution = index;
        }
    }

    if (best_solution) |index| {
        return try solutions.items[index].clone(allocator);
    } else {
        return error.NoSolution;
    }
}

fn printSolution(actions: []const Action) void {
    var is_first = true;
    for (actions) |action| {
        std.debug.print("{f}", .{action});
        if (is_first) {
            @branchHint(.unlikely);
            std.debug.print(" ", .{});
        } else {
            is_first = false;
        }
    }
    std.debug.print("\n", .{});
}

const Plan = enum {
    FileHead,
    ShovelHead,
    HammerHead,
    MiningHammer,
    KnifeHead,
    PickaxeHead,
    AxeHead,
    TongPart,
    Rod,
    Plate,
    SwordHead,
};

fn plansFields() [@typeInfo(Plan).@"enum".fields.len]std.builtin.Type.StructField {
    comptime var recipes_fields: [@typeInfo(Plan).@"enum".fields.len]std.builtin.Type.StructField = undefined;

    inline for (0.., std.meta.fields(Plan)) |ix, plan| {
        recipes_fields[ix] = std.builtin.Type.StructField{
            .name = plan.name,
            .type = Rule,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Rule),
        };
    }
    return recipes_fields;
}

fn plansLayout() std.builtin.Type {
    return comptime .{ .@"struct" = .{
        .is_tuple = false,
        .layout = .auto,
        .fields = &plansFields(),
        .decls = &.{},
    } };
}

fn dataLayout() type {
    return struct {
        plans: @Type(plansLayout()),

        fn getRule(self: @This(), plan: Plan) Rule {
            inline for (std.meta.fields(@TypeOf(self.plans))) |f| {
                if (std.mem.eql(u8, f.name, @tagName(plan))) {
                    return @field(self.plans, f.name);
                }
            }
            unreachable;
        }
    };
}

const data: dataLayout() = @import("data.zon");

pub fn main() !void {
    var debug_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();

    const allocator = debug_allocator.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len != 3) {
        std.debug.print("Usage: tfg_anvil Plan_Name Initial_Target", .{});
        return error.InvalidArguments;
    }

    const plan: Plan = loop: inline for (std.meta.fields(Plan)) |p| {
        if (std.ascii.eqlIgnoreCase(p.name, argv[1])) {
            break :loop @enumFromInt(p.value);
        }
    } else {
        return error.InvalidPlan;
    };

    const initial_target = try std.fmt.parseInt(i32, argv[2], 10);
    const rule = data.getRule(plan);

    var solution = try solve(allocator, initial_target, rule);
    defer solution.deinit(allocator);

    printSolution(solution.items);
}
