# Testbench for the 4-bit Adder / Accumulator

This uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the design
and check its outputs. See the [website](https://tinytapeout.com/hdl/testing/)
for more on how Tiny Tapeout testbenches work in general.

## How to run

To run the RTL simulation:

```sh
make -B
```

To run gate-level simulation, first harden the project and copy
`../runs/wokwi/results/final/verilog/gl/tt_um_taiwoopesade_adder_accumulator.v`
to `gate_level_netlist.v`, then run:

```sh
make -B GATES=yes
```

## How to view the waveform file

```sh
gtkwave tb.fst
```

or, with [Surfer](https://surfer-project.org/):

```sh
surfer tb.fst
```
