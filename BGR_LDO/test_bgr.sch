v {xschem version=3.4.8RC file_version=1.3}
G {}
K {}
V {}
S {}
F {}
E {}
N -530 30 -530 50 {lab=0}
N -530 -70 -530 -30 {lab=VDD}
N 270 -100 300 -100 {lab=#net1}
N 300 -100 430 -100 {lab=#net1}
N 470 -70 470 0 {lab=#net1}
N 410 -50 470 -50 {lab=#net1}
N 230 -70 230 0 {lab=#net1}
N 230 -350 230 -130 {lab=VDD}
N 470 -350 470 -130 {lab=VDD}
N 230 300 230 340 {lab=0}
N 170 270 190 270 {lab=#net2}
N 470 300 470 330 {lab=0}
N 510 270 530 270 {lab=ctat}
N 160 -100 230 -100 {lab=VDD}
N 160 -160 160 -100 {lab=VDD}
N 160 -160 230 -160 {lab=VDD}
N 470 -100 520 -100 {lab=VDD}
N 520 -170 520 -100 {lab=VDD}
N 470 -170 520 -170 {lab=VDD}
N 470 330 470 360 {lab=0}
N 230 340 230 360 {lab=0}
N 230 360 230 450 {lab=0}
N 340 -100 340 -50 {lab=#net1}
N 290 -50 410 -50 {lab=#net1}
N 230 0 230 30 {lab=#net1}
N 270 60 430 60 {lab=#net1}
N 470 0 470 30 {lab=#net1}
N 230 20 300 20 {lab=#net1}
N 300 20 300 60 {lab=#net1}
N 470 60 530 60 {lab=0}
N 230 210 230 240 {lab=#net2}
N 690 140 690 150 {lab=vout}
N 690 210 690 240 {lab=#net3}
N 470 360 690 360 {lab=0}
N 690 300 690 360 {lab=0}
N 470 -350 690 -350 {lab=VDD}
N 690 -350 690 -130 {lab=VDD}
N 470 -50 650 -50 {lab=#net1}
N 650 -100 650 -50 {lab=#net1}
N 690 -100 760 -100 {lab=VDD}
N 760 -170 760 -100 {lab=VDD}
N 690 -170 760 -170 {lab=VDD}
N 620 270 650 270 {lab=#net3}
N 170 230 170 270 {lab=#net2}
N 170 230 230 230 {lab=#net2}
N 470 220 530 220 {lab=ctat}
N 530 220 530 270 {lab=ctat}
N 530 60 550 60 {lab=0}
N 550 60 550 360 {lab=0}
N 230 270 290 270 {lab=0}
N 290 270 290 360 {lab=0}
N 420 270 470 270 {lab=0}
N 420 270 420 360 {lab=0}
N 620 220 620 270 {lab=#net3}
N 620 220 690 220 {lab=#net3}
N 690 270 720 270 {lab=0}
N 720 270 720 350 {lab=0}
N 690 360 720 360 {lab=0}
N 720 350 720 360 {lab=0}
N 230 -50 290 -50 {lab=#net1}
N 160 60 230 60 {lab=0}
N 230 360 470 360 {lab=0}
N 230 -350 470 -350 {lab=VDD}
N 160 60 160 360 {lab=0}
N 160 360 230 360 {lab=0}
N 690 50 780 50 {lab=vout}
N 690 -70 690 20 {lab=vout}
N 470 210 470 240 {lab=ctat}
N 690 130 690 140 {lab=vout}
N 690 20 690 70 {lab=vout}
N 230 150 230 210 {lab=#net2}
N 230 90 230 150 {lab=#net2}
N 470 90 470 150 {lab=#net4}
N 690 70 690 130 {lab=vout}
C {devices/code_shown.sym} -680 -550 0 0 {name=MODELS only_toplevel=true
format="tcleval( @value )"
value="
.include $::180MCU_MODELS/design.ngspice
.lib $::180MCU_MODELS/sm141064.ngspice typical
.lib $::180MCU_MODELS/sm141064.ngspice res_typical
.lib $::180MCU_MODELS/sm141064.ngspice moscap_typical
.lib $::180MCU_MODELS/sm141064.ngspice bjt_typical
"}
C {devices/code_shown.sym} 620 -580 0 0 {name=NGSPICE only_toplevel=true
value="

.control
save all
*tran 1p 100n
dc temp -50 125 5

write bandgap_tb.raw
.endc
"}
C {vdd.sym} 290 -350 0 0 {name=l2 lab=VDD}
C {gnd.sym} 230 450 0 0 {name=l5 lab=0}
C {vdd.sym} -530 -70 0 0 {name=l1 lab=VDD}
C {vsource.sym} -530 0 0 0 {name=V1 value=3.3 savecurrent=true}
C {gnd.sym} -530 50 0 0 {name=l3 lab=0}
C {symbols/pfet_03v3.sym} 450 -100 0 0 {name=M1
L=0.4u
W=2u
nf=1
m=7
ad="'int((nf+1)/2) * W/nf * 0.18u'"
pd="'2*int((nf+1)/2) * (W/nf + 0.18u)'"
as="'int((nf+2)/2) * W/nf * 0.18u'"
ps="'2*int((nf+2)/2) * (W/nf + 0.18u)'"
nrd="'0.18u / W'" nrs="'0.18u / W'"
sa=0 sb=0 sd=0
model=pfet_03v3
spiceprefix=X
}
C {symbols/pfet_03v3.sym} 250 -100 0 1 {name=M4
L=0.4u
W=2u
nf=1
m=7
ad="'int((nf+1)/2) * W/nf * 0.18u'"
pd="'2*int((nf+1)/2) * (W/nf + 0.18u)'"
as="'int((nf+2)/2) * W/nf * 0.18u'"
ps="'2*int((nf+2)/2) * (W/nf + 0.18u)'"
nrd="'0.18u / W'" nrs="'0.18u / W'"
sa=0 sb=0 sd=0
model=pfet_03v3
spiceprefix=X
}
C {symbols/nfet_03v3.sym} 450 60 0 0 {name=M6
L=0.4u
W=2u
nf=1
m=7
ad="'int((nf+1)/2) * W/nf * 0.18u'"
pd="'2*int((nf+1)/2) * (W/nf + 0.18u)'"
as="'int((nf+2)/2) * W/nf * 0.18u'"
ps="'2*int((nf+2)/2) * (W/nf + 0.18u)'"
nrd="'0.18u / W'" nrs="'0.18u / W'"
sa=0 sb=0 sd=0
model=nfet_03v3
spiceprefix=X
}
C {symbols/nfet_03v3.sym} 250 60 0 1 {name=M7
L=0.4u
W=2u
nf=1
m=7
ad="'int((nf+1)/2) * W/nf * 0.18u'"
pd="'2*int((nf+1)/2) * (W/nf + 0.18u)'"
as="'int((nf+2)/2) * W/nf * 0.18u'"
ps="'2*int((nf+2)/2) * (W/nf + 0.18u)'"
nrd="'0.18u / W'" nrs="'0.18u / W'"
sa=0 sb=0 sd=0
model=nfet_03v3
spiceprefix=X
}
C {res.sym} 470 180 0 0 {name=R1
value=200ohm
footprint=1206
device=resistor
m=1}
C {lab_pin.sym} 470 210 0 0 {name=p4 sig_type=std_logic lab=ctat}
C {symbols/pfet_03v3.sym} 670 -100 0 0 {name=M2
L=0.4u
W=2u
nf=1
m=7
ad="'int((nf+1)/2) * W/nf * 0.18u'"
pd="'2*int((nf+1)/2) * (W/nf + 0.18u)'"
as="'int((nf+2)/2) * W/nf * 0.18u'"
ps="'2*int((nf+2)/2) * (W/nf + 0.18u)'"
nrd="'0.18u / W'" nrs="'0.18u / W'"
sa=0 sb=0 sd=0
model=pfet_03v3
spiceprefix=X
}
C {res.sym} 690 180 0 0 {name=R3
value=1450ohm
footprint=1206
device=resistor
m=1}
C {symbols/npn_05p00x05p00.sym} 210 270 0 0 {name=Q1
model=npn_05p00x05p00
spiceprefix=X
m=1}
C {symbols/npn_05p00x05p00.sym} 670 270 0 0 {name=Q2
model=npn_05p00x05p00
spiceprefix=X
m=1}
C {symbols/npn_05p00x05p00.sym} 490 270 0 1 {name=Q3
model=npn_05p00x05p00
spiceprefix=X
m=8}
C {lab_pin.sym} 780 50 2 0 {name=p5 sig_type=std_logic lab=vout}
