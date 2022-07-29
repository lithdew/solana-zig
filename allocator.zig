const std = @import("std");

const heap_start = @intToPtr([*]u8, 0x300000000);
const heap_length = 32 * 1024;

pub const allocator = std.mem.Allocator.init(
    @ptrCast(*Allocator, heap_start),
    Allocator.allocFn,
    Allocator.resizeFn,
    Allocator.freeFn,
);

const Allocator = struct {
    end_index: usize,

    fn isLastAllocation(self: Allocator, buf: []u8) bool {
        return buf.ptr + buf.len == heap_start + self.end_index;
    }

    fn allocFn(
        self: *Allocator,
        n: usize,
        ptr_align: u29,
        _: u29,
        _: usize,
    ) std.mem.Allocator.Error![]u8 {
        if (self.end_index == 0) {
            self.end_index = comptime std.mem.alignPointerOffset(heap_start, @alignOf(Allocator)).? + @sizeOf(Allocator);
        }

        const offset = std.mem.alignPointerOffset(heap_start + self.end_index, ptr_align) orelse {
            return error.OutOfMemory;
        };

        const adjusted_index = self.end_index + offset;
        const new_end_index = adjusted_index + n;

        if (new_end_index > heap_length) {
            return error.OutOfMemory;
        }
        const result = heap_start[adjusted_index..new_end_index];
        self.end_index = new_end_index;

        return result;
    }

    fn resizeFn(
        self: *Allocator,
        buf: []u8,
        _: u29,
        new_size: usize,
        len_align: u29,
        _: usize,
    ) ?usize {
        if (self.end_index == 0) {
            self.end_index = comptime std.mem.alignPointerOffset(heap_start, @alignOf(Allocator)).? + @sizeOf(Allocator);
        }

        if (!self.isLastAllocation(buf)) {
            if (new_size > buf.len) {
                return null;
            }
            return if (new_size == 0) 0 else std.mem.alignAllocLen(buf.len, new_size, len_align);
        }

        if (new_size <= buf.len) {
            const sub = buf.len - new_size;
            self.end_index -= sub;
            return if (new_size == 0) 0 else std.mem.alignAllocLen(buf.len - sub, new_size, len_align);
        }

        const add = new_size - buf.len;
        if (add + self.end_index > heap_length) {
            return null;
        }
        self.end_index += add;
        return new_size;
    }

    fn freeFn(self: *Allocator, buf: []u8, _: u29, _: usize) void {
        if (self.isLastAllocation(buf)) {
            self.end_index -= buf.len;
        }
    }
};
