// SPI interface for external communication. In the chipathon design, we're using memory-mapped SPI
// to offload SHAKE-128 results and health monitor status.

interface spi_if;
    logic sclk; // SPI clock
    logic cs_n; // chip select (active-low)
    logic mosi; // main-out-subordinate-in
    logic miso; // main-in-subordinate-out

    modport main (
        input   sclk,
        output  cs_n,
        output  mosi,
        input   miso
    );

    modport subordinate (
        input   sclk,
        input   cs_n,
        input   mosi,
        output  miso
    );
endinterface
