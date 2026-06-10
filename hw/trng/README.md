# True Random Number Generator

The TRNG is the root of secret generation for LATTICE. It consists of an entropy source with Keccak-based conditioning and integrated health monitoring.

![Block diagram showing the TRNG's components: an entropy source made up of multiple ring oscillators, SHA-3 and SHAKE-128 conditioning, and a health monitor watching the other blocks. Random bit vectors and health monitor status are listed as outputs.](/docs/images/TRNG.png)
