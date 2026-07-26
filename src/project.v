/*
 * Copyright (c) 2026 Taiwo Opesade
 * SPDX-License-Identifier: Apache-2.0
 *
 * 4-bit adder/accumulator with load and clear.
 *
 * This design is built strictly from the same primitive logic-gate cells
 * that Wokwi's schematic editor exposes (AND, OR, XOR, NOT, 2:1 MUX and a
 * D flip-flop with async active-high reset) - see the *_cell modules below.
 * The top-level module only wires instances of these cells together; there
 * is no behavioural (+, *, ?:) arithmetic anywhere in the design.
 */

`default_nettype none

// ---------------------------------------------------------------------------
// Primitive gate cells (the same set Wokwi's logic-gate palette exports to
// Verilog). Kept self-contained here so this file has no dependency on the
// Wokwi-only src/cells.v shim.
// ---------------------------------------------------------------------------

(* keep_hierarchy *)
module and_cell (
    input  wire a,
    input  wire b,
    output wire out
);
  assign out = a & b;
endmodule

(* keep_hierarchy *)
module or_cell (
    input  wire a,
    input  wire b,
    output wire out
);
  assign out = a | b;
endmodule

(* keep_hierarchy *)
module xor_cell (
    input  wire a,
    input  wire b,
    output wire out
);
  assign out = a ^ b;
endmodule

(* keep_hierarchy *)
module not_cell (
    input  wire in,
    output wire out
);
  assign out = !in;
endmodule

(* keep_hierarchy *)
module mux_cell (
    input  wire a,
    input  wire b,
    input  wire sel,
    output wire out
);
  assign out = sel ? b : a;
endmodule

(* keep_hierarchy *)
module dffr_cell (
    input  wire clk,
    input  wire d,
    input  wire r,
    output reg  q,
    output wire notq
);
  assign notq = !q;

  always @(posedge clk or posedge r) begin
    if (r)
      q <= 1'b0;
    else
      q <= d;
  end
endmodule

// ---------------------------------------------------------------------------
// One bit of a ripple-carry full adder, built from and_cell/xor_cell/or_cell.
// sum = a ^ b ^ cin ; cout = (a & b) | (cin & (a ^ b))
// ---------------------------------------------------------------------------

module full_adder_bit (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
  wire p;   // a ^ b, the "propagate" term
  wire g1;  // a & b
  wire g2;  // (a ^ b) & cin

  xor_cell xor_p    (.a(a),  .b(b),   .out(p));
  xor_cell xor_sum   (.a(p),  .b(cin), .out(sum));
  and_cell and_g1    (.a(a),  .b(b),   .out(g1));
  and_cell and_g2    (.a(p),  .b(cin), .out(g2));
  or_cell  or_cout   (.a(g1), .b(g2),  .out(cout));
endmodule

// ---------------------------------------------------------------------------
// One bit of the accumulator register: chooses the next value between
// "add" (adder sum), "load" (raw data input) and "clear" (0), then
// registers it on the next clock edge.
//
//   add_or_load = mode ? data_in : sum
//   next        = clr  ? 0       : add_or_load
// ---------------------------------------------------------------------------

module accumulator_bit (
    input  wire clk,
    input  wire rst_high,   // active-high reset (already inverted from rst_n)
    input  wire sum,
    input  wire data_in,
    input  wire mode,       // 0 = add, 1 = load
    input  wire clr,        // 1 = force next value to 0
    output wire q
);
  wire add_or_load;
  wire next;
  wire unused_notq;

  mux_cell mux_mode (.a(sum),         .b(data_in), .sel(mode), .out(add_or_load));
  mux_cell mux_clr  (.a(add_or_load), .b(1'b0),    .sel(clr),  .out(next));

  dffr_cell reg_bit (
      .clk (clk),
      .d   (next),
      .r   (rst_high),
      .q   (q),
      .notq(unused_notq)
  );
endmodule

// ---------------------------------------------------------------------------
// Top-level Tiny Tapeout wrapper.
//
// Pinout:
//   ui_in[3:0]  DATA_IN - 4-bit operand
//   ui_in[4]    MODE    - 0: ACC <= ACC + DATA_IN   1: ACC <= DATA_IN
//   ui_in[5]    CLR     - 1: ACC <= 0 (overrides MODE)
//   ui_in[7:6]  unused
//
//   uo_out[3:0] ACC        - current accumulator value
//   uo_out[4]   CARRY_OUT  - carry out of the adder (add path)
//   uo_out[5]   ZERO       - 1 when ACC == 4'b0000
//   uo_out[7:6] unused (0)
//
//   uio - all unused, configured as inputs (not driven)
// ---------------------------------------------------------------------------

module tt_um_taiwoopesade_adder_accumulator (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire        ena,     // always 1 when the design is powered, so you can ignore it
    input  wire        clk,     // clock
    input  wire        rst_n    // reset_n - low to reset
);

  wire [3:0] data_in = ui_in[3:0];
  wire       mode    = ui_in[4];
  wire       clr     = ui_in[5];

  wire rst_high;
  not_cell not_rst (.in(rst_n), .out(rst_high));

  wire [3:0] acc;
  wire [3:0] sum;
  wire [4:0] carry;   // carry[0] is the carry-in to bit 0 (always 0)

  assign carry[0] = 1'b0;

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : bits
      full_adder_bit fa (
          .a   (acc[i]),
          .b   (data_in[i]),
          .cin (carry[i]),
          .sum (sum[i]),
          .cout(carry[i+1])
      );

      accumulator_bit accbit (
          .clk     (clk),
          .rst_high(rst_high),
          .sum     (sum[i]),
          .data_in (data_in[i]),
          .mode    (mode),
          .clr     (clr),
          .q       (acc[i])
      );
    end
  endgenerate

  // zero flag: 1 when all accumulator bits are 0 (combinational is fine here -
  // it's just a property of the current stored value, not a stale operation
  // result like the carry below would be if left combinational).
  wire or_01, or_23, or_all, zero;
  or_cell  or_a (.a(acc[0]), .b(acc[1]), .out(or_01));
  or_cell  or_b (.a(acc[2]), .b(acc[3]), .out(or_23));
  or_cell  or_c (.a(or_01),  .b(or_23),  .out(or_all));
  not_cell not_zero (.in(or_all), .out(zero));

  // Carry-out flag: must be REGISTERED, not read straight off the adder.
  // The adder is combinational and continuously re-evaluates against
  // whatever is on data_in right now, so sampling it after the clock edge
  // that used it would show the carry for a *new, different* add (current
  // acc + current data_in), not the carry that actually produced this acc.
  // Latching it in step with the accumulator (and forcing it to 0 on a
  // load or clear, since neither of those is an add) fixes that.
  wire carry_add_or_load, carry_next, carry_flag, unused_carry_notq;
  mux_cell mux_carry_mode (.a(carry[4]),          .b(1'b0), .sel(mode), .out(carry_add_or_load));
  mux_cell mux_carry_clr  (.a(carry_add_or_load),  .b(1'b0), .sel(clr),  .out(carry_next));
  dffr_cell carry_reg (
      .clk (clk),
      .d   (carry_next),
      .r   (rst_high),
      .q   (carry_flag),
      .notq(unused_carry_notq)
  );

  assign uo_out[3:0] = acc;
  assign uo_out[4]   = carry_flag;
  assign uo_out[5]   = zero;
  assign uo_out[7:6] = 2'b00;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in, ui_in[7:6], 1'b0};

endmodule
