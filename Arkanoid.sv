//============================================================================
// 
//  Port to MiSTer.
//  Copyright (C) 2018 Sorgelig
//
//  Arkanoid replica for MiSTer
//  Copyright (C) 2018 Ash Evans (aka ElectronAsh / OzOnE).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,
	
	input			  BTN_USER,
	input			  BTN_OSD,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);


////////////////////   CLOCKS   ///////////////////

wire CLK_6M;
wire CLK_12M;
wire LOCKED;

pll pll
(
	.refclk( CLK_50M ),
	.outclk_0( CLK_6M ),
	.outclk_1( CLK_12M ),
	.locked( LOCKED )
);

T80se T80se_inst
(
	.RESET_n( RESET ) ,	// input  RESET_n
	
	.CLK_n( CLK_6M ) ,	// input  CLK_n
	.CLKEN( 1'b1 ) ,		// input  CLKEN
	
	//.WAIT_n( !HSYNC_CNT[8] ) ,	// input  WAIT_n
	.WAIT_n( 1'b1 ) ,// input  WAIT_n (RUN Z80 when this is HIGH!)
	.INT_n( !Z80_VINT ) ,// input  INT_n
	.NMI_n( 1'b1 ) ,		// input  NMI_n
	.BUSRQ_n( 1'b1 ) ,	// input  BUSRQ_n

	.M1_n( Z80_M1_N ) ,		// output  M1_n
	.MREQ_n( Z80_MREQ_N ) ,	// output  MREQ_n
	.IORQ_n( Z80_IORQ_N ) ,	// output  IORQ_n
	
	.RD_n( Z80_RD_N ) ,	// output  RD_n
	.WR_n( Z80_WR_N ) ,	// output  WR_n
	
	.RFSH_n( RFSH_N ) ,	// output  RFSH_n
	.HALT_n( HALT_N ) ,	// output  HALT_n
	.BUSAK_n( BUSAK_N ) ,// output  BUSAK_n
	
	.A( Z80_ADDR ) ,		// output [15:0] A
	.DI( Z80_DI ) ,		// input [7:0] DI
	.DO( Z80_DO ) 			// output [7:0] DO
);

wire [15:0] Z80_ADDR;
//wire [7:0] Z80_DI;
wire [7:0] Z80_DO;


wire ROM0_CS 	= (Z80_ADDR>=16'h0000 && Z80_ADDR<=16'h7FFF);
wire ROM1_CS 	= (Z80_ADDR>=16'h8000 && Z80_ADDR<=16'hBFFF);
wire RAM_CS 	= (Z80_ADDR>=16'hC000 && Z80_ADDR<=16'hCFFF);	// RAM is apparently mirrored from 0xC800 to 0xCFFF!
//wire RAM_CS 	= (Z80_ADDR>=16'hC000 && Z80_ADDR<=16'hC7FF);
wire AY_CS		= (Z80_ADDR>=16'hD000 && Z80_ADDR<=16'hD001);
wire STATE_CS	= (Z80_ADDR>=16'hD008 && Z80_ADDR<=16'hD008);
wire SYSTEM_CS	= (Z80_ADDR>=16'hD00C && Z80_ADDR<=16'hD00C);
wire BUTTONS_CS= (Z80_ADDR>=16'hD010 && Z80_ADDR<=16'hD010);
wire MCU_CS		= (Z80_ADDR>=16'hD018 && Z80_ADDR<=16'hD018);

wire VRAM_CS	= (Z80_ADDR>=16'hE000 && Z80_ADDR<=16'hEFFF);	// NOTE: VRAM is 4KB, but 16-bit wide. The address gets shifted, so the Z80 can access both bytes.


// NOTE: There is NO separate RAM for this on the real Arkanoid PCB!
// It's just the way the MAME source splits up the RAM for handling sprites makes it seem like these are separate physical RAM chips.
//
//wire SPRITE_CS = (Z80_ADDR>=16'hE800 && Z80_ADDR<=16'hE83F);	// 
//wire TOPRAM_CS	= (Z80_ADDR>=16'hE840 && Z80_ADDR<=16'hEFFF);// And anything written to "TOPRAM" probably gets written to 0xE040 as well!
//
// VRAM is actually 4KB (2K x 16-bit), so the sprite info words get written to VRAM just AFTER the background tile info.
// The upper part of VRAM seems to be used for extra storage for the Z80, like some in-game variables, high-scores etc.
//


wire NOPR_CS	= (Z80_ADDR>=16'hF001 && Z80_ADDR<=16'hFFFF);

wire BOOTLEG_CS = (Z80_ADDR>=16'hF000 && Z80_ADDR<=16'hF000);



(* keep = 1 *) wire [7:0] Z80_DI = //(Z80_ADDR>=16'h038A && Z80_ADDR<=16'h038B) ? 8'h00 :
											  //(Z80_ADDR>=16'h038F && Z80_ADDR<=16'h03BA) ? 8'h00 :
											  (!Z80_IORQ_N) ? 8'hF5 :
											  (ROM0_CS) ? ROM_IC17_DO : 
											  (ROM1_CS) ? ROM_IC16_DO : 
											  (RAM_CS)  ? RAM_DO : 
											  (AY_CS)	  ? AY_DO :
											  (STATE_CS) ? RH_BYTE :		// Reads the unused "RH" joystick stuff, but not used by Arkanoid.
											  (SYSTEM_CS) ? SYSTEM_BYTE :
											  (BUTTONS_CS) ? BUTTONS :
											  //(MCU_CS) ? 8'h5A :
											  (MCU_CS) ? 8'h00 :
											  (VRAM_CS && !Z80_ADDR[0]) ? VRAM_DO[7:0] :	// I think the endianess for reading VRAM is swapped on the real board!
											  (VRAM_CS && Z80_ADDR[0]) ? VRAM_DO[15:8] :	// So, I'm trying that here. OzOnE.
											  //(SPRITE_CS) ? SPRITE_DO :
											  //(TOPRAM_CS) ? TOPRAM_DO :
											  (BOOTLEG_CS) ? 8'hFF :
											  (NOPR_CS) ? 8'hFF :	// Will usually crash if this isn't set to 0xFF? Still not sure why? OzOnE.
											  //(NOPR_CS) ? NOPR_DO :
															 8'hFF;


reg [7:0] NOPR [0:255];
always @(posedge CLK_6M) begin
	if (NOPR_CS & !Z80_WR_N) NOPR[Z80_ADDR[7:0]] <= Z80_DO;
end
wire NOPR_DO = NOPR[Z80_ADDR[7:0]];

wire [7:0] BUTTONS = {4'hF, 4'hF};	// Upper nibble not used? TODO: BUTTON1, COCKTAIL?.


// SYSTEM_BYTE signal "polarity" was gleaned from MAME sources, so probably correct.

wire [1:0] SEMA = 2'b01;	// Active-HIGH. Needs bit 0 of this set HIGH before the animations will work!

wire COIN2 = !BTN_USER;		// Active-HIGH.
wire COIN1 = 1'b0;			// Active-HIGH.
wire TILT = 1'b1;				// Active-LOW.
wire SERVICE1 = 1'b1;		// Active-LOW.
wire START2 = 1'b1;			// Active-LOW.
wire START1 = BTN_OSD;		// Active-LOW.

wire [7:0] SYSTEM_BYTE = {SEMA, COIN2, COIN1, TILT, SERVICE1, START2, START1};


wire P2_L = 1'b0;
wire P2_R = 1'b0;
wire P2_D = 1'b0;
wire P2_U = 1'b0;

wire P1_L = 1'b0;
wire P1_R = 1'b0;
wire P1_D = 1'b0;
wire P1_U = 1'b0;

wire [7:0] RH_BYTE = {P2_L, P2_R, P2_D, P2_U, P1_L, P1_R, P1_D, P1_U};	// THis is called "SYSTEM2" on the MAME address map!


reg [7:0] STATE_REG;

reg [11:0] KEEP_REG/*synthesis noprune*/;
always @(posedge CLK_6M or negedge RESET)
if (!RESET) begin
	STATE_REG <= 8'hFF;	// Check this!!
end
else begin
	//KEEP_REG <= {ROM0_CS, ROM1_CS, RAM_CS, AY_CS, STATE_CS, SYSTEM_CS, BUTTONS_CS, MCU_CS, VRAM_CS, SPRITE_CS, TOPRAM_CS, NOPR_CS};
	KEEP_REG <= {ROM0_CS, ROM1_CS, RAM_CS, AY_CS, STATE_CS, SYSTEM_CS, BUTTONS_CS, MCU_CS, VRAM_CS, 1'b0, 1'b0, NOPR_CS};
	
	if (STATE_CS & !Z80_WR_N) STATE_REG <= Z80_DO;
end



reg Z80_VINT;

always @(posedge CLK_6M or negedge RESET)
if (!RESET) begin
	Z80_VINT <= 1'b0;
end
else begin
	if (!Z80_IORQ_N && !Z80_M1_N) Z80_VINT <= 1'b0;		// Z80 Interrupt Acknowledge, apparently. T80 seems to do this.
	
	if (VSYNC_CNT==248 && HSYNC_CNT==128) Z80_VINT <= 1'b1;
end


ic17	ic17_inst (
	.address ( Z80_ADDR[14:0] ),
	.clock ( CLK_6M ),
	.q ( ROM_IC17_DO )
);
wire [7:0] ROM_IC17_DO;


ic16	ic16_inst (
	.address ( Z80_ADDR[14:0] ),
	.clock ( CLK_6M ),
	.q ( ROM_IC16_DO )
);
wire [7:0] ROM_IC16_DO;


ram	ram_inst (
	.clock ( CLK_6M ),
	
	.address ( Z80_ADDR[10:0] ),
	
	
	.data ( Z80_DO ),
	.wren ( RAM_CS & !Z80_WR_N ),
	
	.q ( RAM_DO )
);
wire [7:0] RAM_DO;



//(* keep = 1 *) wire [10:0] VRAM_ADDR = (VRAM_CS) ? Z80_ADDR[11:1] :
//													            {LINECNT[8:4], PIXCNT[8:4]} - 40;

wire [1:0] VRAM_BE = (!Z80_ADDR[0]) ? 2'b01 : 2'b10;
vram	vram_inst (
	.clock ( CLK_6M ),
	
	.address ( VRAM_ADDR ),
		
	.data ( {Z80_DO,Z80_DO} ),
	.byteena( VRAM_BE ),
	.wren ( VRAM_CS & !Z80_WR_N ),
	
	.q ( VRAM_DO )
);
(* keep = 1 *) wire [15:0] VRAM_DO;


/*
wire [8:0] SPRITE_ADDR = !HSYNC_CNT[8] ? {1'b0, SP_X_POS+SP_PIX_CNT} :	// Use horizontal position (X) value of the sprite from VRAM to address the Sprite RAM.
									              {1'b0, HSYNC_CNT[7:0]};			// Else, during the active line, just use the HSYNC_CNT to increment through the sprite RAM pixels.

wire [7:0] SPRITE_DI = !HSYNC_CNT[8] ? {SP_COLOUR, SHIFT_62, SHIFT_63, SHIFT_64} :	// During sprite tile fetch, write the sprite tile pixel data.
													8'h00;													// Else, write 0x00 to clear the sprite RAM pixels after reading the current data.


spriteram	spriteram_inst (
	.clock ( CLK_6M ),
	
	.address ( SPRITE_ADDR ),
	.data ( SPRITE_DI ),
	.wren( SPRITE_WREN ),
	.q ( SPRITE_DO )
);
wire [7:0] SPRITE_DO;
*/

wire [7:0] SPRITE_DI = !HSYNC_CNT[8] ? {SP_COLOUR, SHIFT_62, SHIFT_63, SHIFT_64} :	// During sprite tile fetch, write the sprite tile pixel data.
													8'h00;													// Else, write 0x00 to clear the sprite RAM pixels after reading the current data.

//wire [8:0] SP_WR_ADDR = !HSYNC_CNT[8] ? {1'b0, SP_X_POS+SP_PIX_CNT} :
wire [8:0] SP_WR_ADDR = !HSYNC_CNT[8] ? {1'b0, SP_X_POS+HSYNC_CNT[2:0]} :
														SP_RD_ADDR - 1;

//wire [8:0] SP_RD_ADDR = !HSYNC_CNT[8] ? {1'b0, SP_X_POS+SP_PIX_CNT} :	// Use horizontal position (X) value of the sprite from VRAM to address the Sprite RAM.
wire [8:0] SP_RD_ADDR = !HSYNC_CNT[8] ? {1'b0, SP_X_POS+HSYNC_CNT[2:0]} :	// Use horizontal position (X) value of the sprite from VRAM to address the Sprite RAM.
														{1'b0, HSYNC_CNT[7:0]};			// Else, during the active line, just use the HSYNC_CNT to increment through the sprite RAM pixels.

spram	spram_inst (
	.clock ( CLK_6M ),
	
	.wraddress ( SP_WR_ADDR ),
	.data ( SPRITE_DI ),
	.wren ( SPRITE_WREN ),
	
	.rdaddress ( SP_RD_ADDR ),
	.q ( SPRITE_DO )
);
wire [7:0] SPRITE_DO/*synthesis keep*/;


// Sprite RAM (actually just written to VRAM)...
//
// Each sprite is represented in sprite RAM by four bytes...
//
// Byte 0 is the X position.
// Byte 1 is the Y position.
// Byte 2, bits [1:0] form the upper bits [9:8] of the tile index.
// Byte 3 forms the lower bits [7:0] of the tile index.
// 
// Byte 2, bits [7:3] form the sprite palette selection (along with the palette bank bit, which is grabbed separately.)
//
//
//
// The Z80 is little-endian, though, so the bytes are swapped here!
//
// Here's an example of the first 8 bytes of VRAM, taken from Arkanoid while it's playing the attract demo.
// (There is no separate "sprite info" RAM on the real board, AFAIK, which caused confusion due to the way MAME handles the sprites.)
//
// Sprite tile 1   Sprite tile 2   etc.
//  C5 EC F2 40     B5 EC F3 40
//
// The C5 and B5 bytes are changing as the paddle moves, so those are the Y positions (landscape!!!) of the two tiles.
// (the paddle is normally made from two tiles, hence the slight Y offset of C5 and B5).
//
// EC is the tile X position (landscape). (same for both tiles here, obviously, as it's a vertical paddle). Again - LANDSCAPE ROTATION!! lol
//
// F2 forms the lower bits [7:0] of the tile index.
//
// Bits [1:0] of 40 forms the upper bits [9:8] of the tile index.
//
//
//
// During the time when the HSYNC Counter is between 128 (0x80) and 255 (0xFF), the "sprite info" values are grabbed from VRAM (start from WORD offset 0x400).
//
// The real Arkanoid PCB uses a pair of 74LS283 chips (4-bit full adders. IC61 and IC60), which form an 8-bit adder.
// The 8-bit adder is used to compare the Y position of the sprite tile from VRAM with the current VSYNC Counter value.
//
// If the VSYNC Counter (line counter) value is equal or greater than the sprite tile offset, writing is enabled to what I call the "sprite line buffer", IC51.
// This is a 512-BYTE RAM, and I believe it stores the pixel data for each line, but only for the sprite tiles.
//
// When bit [8] of the HSYNC Counter is LOW (128 to 255), the HPOS (X position of the current sprite tile) is used to address RAM IC51.
//
// The pixel data for that tile is then written to that RAM at an address that represents the sprite tile position along the horizontal line.
// 
// Then, during the active video line (HSYNC Counter between 256 and 511), a pair of 4-bit counters (IC52 and IC65) form an 8-bit counter
// which is used to increment the through the addresses of "sprite line buffer" RAM IC51.
//
// If the any of the lower 3 bits being output from RAM IC51 are High, then the pixel data from RAM IC51 get displayed video the video output instead of the background tile pixel(s).
// That is done using a pair of 74LS298 mux chips (IC38 and IC39).
//


/*
topram	topram_inst (
	.address ( Z80_ADDR[10:0] ),
	.clock ( CLK_6M ),
	.data ( Z80_DO ),
	.wren ( TOPRAM_CS & !Z80_WR_N ),
	.q ( TOPRAM_DO )
);
wire [7:0] TOPRAM_DO;
*/

// BDIR  BC  MODE
//   0   0   inactive
//   0   1   read value
//   1   0   write value
//   1   1   set address

YM2149 YM2149_inst
(
	.CLK( CLK_6M ) ,	// input  CLK
	
	.CE( HSYNC_CNT[1:0]==0 ) ,	// input  CE
	
	.RESET( !RESET ) ,	// input  RESET
	
	.BDIR( AY_CS & !Z80_WR_N ) ,	// input  BDIR
	.BC( !Z80_ADDR[0] ) ,			// input  BC
	
	.DI( Z80_DO ) ,	// input [7:0] DI
	.DO( AY_DO ) ,		// output [7:0] DO
	
	.CHANNEL_A(CHANNEL_A) ,	// output [7:0] CHANNEL_A
	.CHANNEL_B(CHANNEL_B) ,	// output [7:0] CHANNEL_B
	.CHANNEL_C(CHANNEL_C) ,	// output [7:0] CHANNEL_C
	
//	.SEL(SEL) ,		// input  SEL
//	.MODE(MODE) ,	// input  MODE
	
//	.ACTIVE(ACTIVE) ,		// output [5:0] ACTIVE
	
	.IOA_in(IOA_in) ,		// input [7:0] IOA_in
	.IOA_out(IOA_out) ,	// output [7:0] IOA_out
	.IOB_in(IOB_in) ,		// input [7:0] IOB_in
	.IOB_out(IOB_out) 	// output [7:0] IOB_out
);

wire [7:0] IOA_in;
wire [7:0] IOA_out;

wire [7:0] IOB_in = {DIPSW[0], DIPSW[1], DIPSW[2], DIPSW[3], DIPSW[4], DIPSW[5], DIPSW[6], DIPSW[7]};
wire [7:0] IOB_out;


wire [7:0] DIPSW = 8'b00100000;

/*DIP Switches
+-----------------------------+--------------------------------+
|FACTORY DEFAULT = *          |  1   2   3   4   5   6   7   8 |
+----------+------------------+----+---+-----------------------+
|          |*1 COIN  1 CREDIT | OFF|OFF|                       |
|COINS     | 1 COIN  2 CREDITS| ON |OFF|                       |
|          | 2 COINS 1 CREDIT | OFF|ON |                       |
|          | 1 COIN  6 CREDITS| ON |ON |                       |
+----------+------------------+----+---+---+                   |
|LIVES     |*3                |        |OFF|                   |
|          | 5                |        |ON |                   |
+----------+------------------+--------+---+---+               |
|BONUS     |*20000 / 60000    |            |OFF|               |
|1ST/EVERY | 20000 ONLY       |            |ON |               |
+----------+------------------+------------+---+---+           |
|DIFFICULTY|*EASY             |                |OFF|           |
|          | HARD             |                |ON |           |
+----------+------------------+----------------+---+---+       |
|GAME MODE |*GAME             |                    |OFF|       |
|          | TEST             |                    |ON |       |
+----------+------------------+--------------------+---+---+   |
|SCREEN    |*NORMAL           |                        |OFF|   |
|          | INVERT           |                        |ON |   |
+----------+------------------+------------------------+---+---+
|CONTINUE  | WITHOUT          |                            |OFF|
|          |*WITH             |                            |ON |
+----------+------------------+----------------------------+---+
*/



wire [7:0] AY_DO;

wire [5:0] ACTIVE;

wire [7:0] CHANNEL_A;
wire [7:0] CHANNEL_B;
wire [7:0] CHANNEL_C;


wire [9:0] audio_l = { 1'b0, CHANNEL_A, 1'b0 } + { 2'b00, CHANNEL_B };
wire [9:0] audio_r = { 1'b0, CHANNEL_C, 1'b0 } + { 2'b00, CHANNEL_B };

assign AUDIO_L   = {audio_l, 6'd0};
assign AUDIO_R   = {audio_r, 6'd0};
assign AUDIO_S = 1'b0;
assign AUDIO_MIX = 2'd0;



reg [4:0] BG_COLOUR_1;
reg [4:0] BG_COLOUR_2;
reg [4:0] BG_COLOUR;
reg [10:0] BG_INDEX;

always @(posedge CLK_6M) begin
	// Fudge. Just for testing...
	BG_COLOUR_1 <= VRAM_DO[7:3];
	BG_COLOUR_2 <= BG_COLOUR_1;
	BG_COLOUR <= BG_COLOUR_2;
		
	BG_INDEX <= {VRAM_DO[2:0], VRAM_DO[15:8]};
end



//Bits written to IC51...

/*
wire [7:0] IC51_DI = {COLOUR, DOT[2:0]};	// "DOT" on the schematic is actually the output from the MB112S custom shifter chips!
														// Which I've called {SHIFT_62, SHIFT_63, SHIFT_64} in this Verilog file.


wire [4:0] ADDER_61 = VRAM_DO[3:0] + VSYNC_CNT[3:0];
wire [4:0] ADDER_60 = VRAM_DO[7:4] + VSYNC_CNT[7:4] + ADDR_61[4];	// Add the Carry from the previous adder!

wire NAND_75 = !(ADDER_60[3] & ADDER_60[2] & ADDER_60[1] & ADDER_60[0]);
*/


//wire [3:0] MUX_47 = (!HSYNC_CNT[8]) ? ADDER_61[3:0] : ?????;
//wire [3:0] MUX_48 = (!HSYNC_CNT[8]) ? VRAM_DO[3:0] : VRAM_DO[4:1];
//wire [3:0] MUX_49 = (!HSYNC_CNT[8]) ? VRAM_DO[7:4] : VRAM_DO[8:5];
//wire [3:0] MUX_50 = (!HSYNC_CNT[8]) ? ???? : ????;


														
//wire [13:0] SRA_MUX = (!HSYNC_CNT[8]) ? 


wire FLIP_X    = STATE_REG[0];
wire FLIP_Y    = STATE_REG[1];
wire PAD_SEL   = STATE_REG[2];
wire COIN_LOCK = STATE_REG[3];
wire DONT_KNOW = STATE_REG[4];
wire GFX_BANK  = STATE_REG[5];
wire PAL_BANK  = STATE_REG[6];
wire MCU_RESET = STATE_REG[7];


// TILE ROM Address...
//
// BG_INDEX is 11 bits [10:0], then we use the lower three bits of VSYNC_CNT to step through each tile row byte in the tile ROM(s).
//
// SP_INDEX is only 10 bits [9:0], though, but SP_TILE_ROW is 4 bits [3:0], because each sprite tile is actually 16 rows tall.
//
// Now it makes sense why the lower FOUR bits of the adder (IC60/IC61) result are used on the original board.
//
//
// BACKGROUND TILES (8x8 pixels)...
// SRA = {GFX_BANK, BG_INDEX[10:0], VSYNC_CNT[2:0]};
//
//
// SPRITE TILES (8x16 pixels)...
// SRA = {GFX_BANK, SP_INDEX[9:0], SP_TILE_ROW[3:0]};
//
//
(* keep = 1 *) wire [14:0] SRA = (!HSYNC_CNT[8]) ? {GFX_BANK, SP_INDEX, SP_TILE_ROW} :		// Sprite tile fetch.
																	{GFX_BANK, BG_INDEX, VSYNC_CNT[2:0]};	// Background tile fetch.


// Tile ROMS...
//
rom_64	rom_64_inst (
	.address ( SRA ),
	.clock ( CLK_6M ),
	.q ( ROM_64_DO )
);
wire [7:0] ROM_64_DO;

rom_63	rom_63_inst (
	.address ( SRA ),
	.clock ( CLK_6M ),
	.q ( ROM_63_DO )
);
wire [7:0] ROM_63_DO;

rom_62	rom_62_inst (
	.address ( SRA ),
	.clock ( CLK_6M ),
	.q ( ROM_62_DO )
);
wire [7:0] ROM_62_DO;


reg SHIFT_64, SHIFT_63, SHIFT_62;

// TODO - Fix the shifter, to properly account for the clock delay of VRAM and the Tile ROMs.
always @(posedge CLK_6M) begin
	SHIFT_64 <= (SHIFT_D==0) ? ROM_64_DO[7] :
					(SHIFT_D==1) ? ROM_64_DO[6] :
					(SHIFT_D==2) ? ROM_64_DO[5] :
					(SHIFT_D==3) ? ROM_64_DO[4] :
					(SHIFT_D==4) ? ROM_64_DO[3] :
					(SHIFT_D==5) ? ROM_64_DO[2] :
					(SHIFT_D==6) ? ROM_64_DO[1] : ROM_64_DO[0];
					 
	SHIFT_63 <= (SHIFT_D==0) ? ROM_63_DO[7] :
					(SHIFT_D==1) ? ROM_63_DO[6] :
					(SHIFT_D==2) ? ROM_63_DO[5] :
					(SHIFT_D==3) ? ROM_63_DO[4] :
					(SHIFT_D==4) ? ROM_63_DO[3] :
					(SHIFT_D==5) ? ROM_63_DO[2] :
					(SHIFT_D==6) ? ROM_63_DO[1] : ROM_63_DO[0];

	SHIFT_62 <= (SHIFT_D==0) ? ROM_62_DO[7] :
					(SHIFT_D==1) ? ROM_62_DO[6] :
					(SHIFT_D==2) ? ROM_62_DO[5] :
					(SHIFT_D==3) ? ROM_62_DO[4] :
					(SHIFT_D==4) ? ROM_62_DO[3] :
					(SHIFT_D==5) ? ROM_62_DO[2] :
					(SHIFT_D==6) ? ROM_62_DO[1] : ROM_62_DO[0];
end


// Palette ROMS...
//
wire [8:0] PAL_ADDR = (SPRITE_DO[2:0]>0) ? {PAL_BANK, SPRITE_DO} :										// The sprite RAM directly stores the Sprite index and colour in each byte (for each pixel).
														 {PAL_BANK, BG_COLOUR, SHIFT_62, SHIFT_63, SHIFT_64};	// The background pixels get shifted out directly, during each visible line.

rom_22	rom_22_inst (
	.address ( PAL_ADDR ),
	.clock ( CLK_6M ),
	.q ( ROM_22_DO )
);
wire [7:0] ROM_22_DO;

rom_23	rom_23_inst (
	.address ( PAL_ADDR ),
	.clock ( CLK_6M ),
	.q ( ROM_23_DO )
);
wire [7:0] ROM_23_DO;

rom_24	rom_24_inst (
	.address ( PAL_ADDR ),
	.clock ( CLK_6M ),
	.q ( ROM_24_DO )
);
wire [7:0] ROM_24_DO;



reg [7:0] VGA_R_REG;
reg [7:0] VGA_G_REG;
reg [7:0] VGA_B_REG;

always @(posedge CLK_6M) begin
	VGA_R_REG <= (!VGA_BLANK) ? {ROM_24_DO[3:0], 4'h0} : 8'h00;
	VGA_G_REG <= (!VGA_BLANK) ? {ROM_23_DO[3:0], 4'h0} : 8'h00;
	VGA_B_REG <= (!VGA_BLANK) ? {ROM_22_DO[3:0], 4'h0} : 8'h00;
end


assign VGA_R = VGA_R_REG;
assign VGA_G = VGA_G_REG;
assign VGA_B = VGA_B_REG;



/*
reg [9:0] PIXCNT;
reg [9:0] LINECNT;

reg HSYNC, VSYNC;

reg [2:0] SHIFT_D;

always @(posedge SYS_CLK) begin
	if(PIXCNT==799) begin
	  PIXCNT <= 0;
	  if (LINECNT == 524) LINECNT <= 0;
	  else LINECNT <= LINECNT + 1;
	end
	else begin
		PIXCNT <= PIXCNT + 1;
	end
	  
  HSYNC <= (PIXCNT>=16 && PIXCNT<=112);	// active for 96 pixels
  VSYNC <= (LINECNT>=10 && LINECNT<=12);	// active for 2 lines
  
	SHIFT_D <= PIXCNT[3:1] - 1;  
end

wire VGA_BLANK = !( (PIXCNT>=160 && PIXCNT<800) && (LINECNT>=45 && LINECNT<525) );

assign VGA_HS = !HSYNC;
assign VGA_VS = !VSYNC;
*/


reg [8:0] HSYNC_CNT;
reg [8:0] VSYNC_CNT;

reg [2:0] SHIFT_D;
always @(posedge CLK_6M) begin
	if (HSYNC_CNT==9'd511) begin
		HSYNC_CNT <= 9'd128;
		
		if (VSYNC_CNT==9'd511) VSYNC_CNT <= 9'd248;
		else VSYNC_CNT <= VSYNC_CNT + 9'd1;
	end
	else HSYNC_CNT <= HSYNC_CNT + 9'd1;
	
	//if (!HSYNC_CNT[8]) SHIFT_D <= SP_PIX_CNT;	// Sprite tile fetch.
	if (!HSYNC_CNT[8]) SHIFT_D <= HSYNC_CNT[2:0];	// Sprite tile fetch.
	else SHIFT_D <= HSYNC_CNT[2:0] - 2;			// BG tile fetch.
end

// The "HSYNC counter" counts from 128 to 511, so 383 6MHz clocks per line. (63.833us per line).

// The "VSYNC counter" counts from 248 to 511, so 263 lines. (16.788167 ms per frame / field). 59.5657Hz.


// When bit [8] of HSYNC_CNT is LOW, addresses 0x400 to 0x41F in VRAM are accessed, to grab the sprite info words.
// (WORD addressed, so from the Z80 point-of-view, addresses 0xE800 to 0xE83F in VRAM are where the sprite info words get written.)

// When bit [8] of HSYNC_CNT is HIGH, addresses 0x040 to 0x7FF (I think) in VRAM are accessed, to grab the background tile words.
// (WORD addressed, so from the Z80 point-of-view, addresses 0xE080 to 0xEFFF in VRAM are where the background tile words get written.)

wire [10:0] MUX_72_71_70 = (!HSYNC_CNT[8]) ? {6'b100000, HSYNC_CNT[6:2]} :					// Sprite info access.     0x0400 to 0x041F. (VRAM WORD address).
														   {1'b0, VSYNC_CNT[7:3], HSYNC_CNT[7:3]};	// Background tile access. 0x0040 to 0x07FF. (VRAM WORD address).

// When bit [0] of HSYNC_CNT is HIGH, the address from the Mux(es) above is used to address VRAM.
//
// When bit [0] of HSYNC_CNT is LOW, the address from the Z80 is used to address VRAM.
// (bits [11:1] of Z80_ADDR are used, as bit [0] is used to select either the upper or lower byte of the VRAM SRAMs.)
//wire [10:0] VRAM_ADDR = (HSYNC_CNT[0]) ? MUX_72_71_70 : 
//								(VRAM_CS) : Z80_ADDR[11:1];


reg [15:0] SPRITE_XY_OFFS_TEMP/*synthesis noprune*/;
reg [7:0] SP_Y_POS/*synthesis noprune*/;
reg [7:0] SP_X_POS/*synthesis noprune*/;

reg [2:0] SP_PIX_CNT/*synthesis noprune*/;

reg [15:0] SPRITE_IND_COL_TEMP/*synthesis noprune*/;
reg [9:0] SP_INDEX/*synthesis noprune*/;
reg [4:0] SP_COLOUR/*synthesis noprune*/;


reg [3:0] SP_TILE_ROW;

reg SPRITE_WREN;

always @(posedge CLK_6M) begin
	if (!HSYNC_CNT[8]) begin
		if (HSYNC_CNT[2:0]==3'd1) SPRITE_XY_OFFS_TEMP <= VRAM_DO;
		if (HSYNC_CNT[2:0]==3'd5) SPRITE_IND_COL_TEMP <= VRAM_DO;
		
		SP_PIX_CNT <= SP_PIX_CNT + 1;
		
		if (HSYNC_CNT[2:0]==3'd7) begin
			SP_Y_POS <= SPRITE_XY_OFFS_TEMP[15:8];
			SP_X_POS <= SPRITE_XY_OFFS_TEMP[7:0];
			SP_INDEX  <= {SPRITE_IND_COL_TEMP[1:0],SPRITE_IND_COL_TEMP[15:8]};
			SP_COLOUR <= SPRITE_IND_COL_TEMP[6:2];
			SP_PIX_CNT <= 3'd7;
			SP_TILE_ROW <= ADDER_61_60[3:0];	// Sprite tiles are 16 pixels tall! The lower four bits of the adder SHOULD select the correct tile ROM row.
		end
	end
	
	// This basically tests for "is there (part of) a sprite tile on this line?"...
	SPRITE_WREN <= (!HSYNC_CNT[8]) ? ADDER_61_60[7:4]==4'b1111 :	// <- During sprite tile fetch / sprite RAM update.
												1'b1;									// <- During each visible line, where the PREVIOUS sprite pixel gets cleared to zero.
end

// When the upper four bits of the Adder are all HIGH, it's basically saying...
//
// if (VSYNC_CNT>=SP_Y_POS && VSYNC_CNT<=SP_Y_POS+16).
//
// We can then use the lower four bits as a remainder, to increment through the 16 rows of the current sprite tile.
// (which is essentially what the original hardware does.)
//wire [7:0] ADDER_61_60 = SP_Y_POS + VSYNC_CNT[7:0];
wire [7:0] ADDER_61_60 = SPRITE_XY_OFFS_TEMP[15:8] + VSYNC_CNT[7:0];



// HSYNC_CNT...
//
// 128 to 255     256 to 511
//
// (128 pixels)   (256 pixels)
// 
// SPRITE FETCH	BG FETCH       
//
// Z80 RUNNING?   Z80 WAIT?
//
// HBLANK         ACTIVE LINE
//
//
wire [10:0] VRAM_ADDR = (VRAM_CS) ? Z80_ADDR[11:1] :
												MUX_72_71_70;


// Horzontal sync PULSE appears to be active when HSYNC_CNT is between 176 and 191, so 15 clocks, or 2.5us.
//wire HS_PULSE = (HSYNC_CNT>=9'd176 && HSYNC_CNT<=9'd191);
wire HS_PULSE = (HSYNC_CNT>=9'd200 && HSYNC_CNT<=9'd216);


// Vertcal sync PULSE appears to be active when VSYNC_CNT is between 256 and 263, so 7 lines, or 446.8333us.
//wire VS_PULSE = (VSYNC_CNT>=9'd256 && VSYNC_CNT<=9'd263);
wire VS_PULSE = (VSYNC_CNT>=9'd263 && VSYNC_CNT<=9'd268);


wire VGA_BLANK = (HSYNC_CNT>=140 && HSYNC_CNT<=256) || (VSYNC_CNT>=240 && VSYNC_CNT<=269);

assign VGA_HS = !HS_PULSE;
assign VGA_VS = !VS_PULSE;


endmodule

/*
    0000 7fff ROM
    
	 8000 bfff bank switch rom space??
    
	 c000 c7ff RAM
    
	 e000 e7ff video ram
    
	 e800-efff unused RAM
	 
    read:
    d001      AY8910 read
    
	 f000      ???????
    
	 write:
    d000      AY8910 control
    
	 d001      AY8910 write
	 
    d008      bit 0   flip screen x
              bit 1   flip screen y
              bit 2   paddle player select
              bit 3   coin lockout
              bit 4   ????????
              bit 5 = graphics bank
              bit 6 = palette bank
              bit 7 = mcu reset
    
	 d010      watchdog reset, or IRQ acknowledge, or both
    
	 f000      ????????
*/
