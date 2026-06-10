// SPI interface for external communication. In the chipathon design, we're using memory-mapped SPI
// to offload SHAKE-128 results and health monitor status.

interface spi_if;
    logic clk;
    logic select;
    logic mosi;
    logic miso;

    modport main (
        input   clk,
        output  select,
        output  mosi,
        input   miso
    );

    modport subordinate (
        input   clk,
        input   select,
        input   mosi,
        output  miso
    );
endinterface
