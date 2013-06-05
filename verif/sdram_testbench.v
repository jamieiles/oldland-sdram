`timescale 1ns/1ps

module sdram_testbench();

reg clk = 1'b0;
wire clk180 = ~clk;

always #10 clk = ~clk;

wire [15:0] h_wdata;
wire [15:0] h_rdata;
reg [31:0] h_addr = 32'h00000000;
wire h_wr_en = ~write_done;
reg [1:0] h_bytesel = 2'b00;
wire h_compl;
wire h_config_done;

wire s_ras_n;
wire s_cas_n;
wire s_wr_en;
wire [1:0] s_bytesel;
wire [12:0] s_addr;
wire s_cs_n;
wire s_clken;
wire [15:0] s_data;
wire [1:0] s_banksel;
reg pattern_sel = 0;

test_pattern_gen tpg(.pattern_sel(pattern_sel),
		     .addr(h_addr),
		     .data(h_wdata));

sdram_controller ctrl(.clk(clk),
		      .h_addr(h_addr),
		      .h_wr_en(h_wr_en),
		      .h_bytesel(h_bytesel),
		      .h_compl(h_compl),
		      .h_wdata(h_wdata),
		      .h_rdata(h_rdata),
		      .h_config_done(h_config_done),
		      .s_ras_n(s_ras_n),
		      .s_cas_n(s_cas_n),
		      .s_wr_en(s_wr_en),
		      .s_bytesel(s_bytesel),
		      .s_addr(s_addr),
		      .s_cs_n(s_cs_n),
		      .s_clken(s_clken),
		      .s_data(s_data),
		      .s_banksel(s_banksel));

mt48lc16m16a2 ram_model(.Dq(s_data),
			.Addr(s_addr),
			.Ba(s_banksel),
			.Clk(clk180),
			.Cke(s_clken),
			.Cs_n(s_cs_n),
			.Ras_n(s_ras_n),
			.Cas_n(s_cas_n),
			.We_n(s_wr_en),
			.Dqm(s_bytesel));

initial begin
	$dumpfile("sdram.vcd");
	$dumpvars(0, sdram_testbench);
	#30000000 $finish;
end

localparam STATE_RESET	= 3'b000;
localparam STATE_IDLE	= 3'b001;
localparam STATE_WRITE	= 3'b011;
localparam STATE_READ	= 3'b010;
localparam STATE_INC	= 3'b110;

reg [2:0] state = STATE_RESET;
reg [2:0] next_state = STATE_RESET;
reg write_done = 1'b0;

always @(*) begin
	case (state)
	STATE_RESET: begin
		if (h_compl)
			next_state = STATE_IDLE;
	end
	STATE_IDLE: begin
		next_state = write_done ? STATE_READ : STATE_WRITE;
	end
	STATE_WRITE: begin
		if (h_compl)
			next_state = STATE_INC;
	end
	STATE_READ: begin
		if (h_compl) begin
			next_state = STATE_INC;
			if (h_rdata != h_wdata) begin
				$display("ERROR: expected %x at address %x, got %x",
					h_addr, h_addr, h_rdata);
				$finish;
			end
		end
	end
	STATE_INC: begin
		next_state = STATE_IDLE;
	end
	default: begin
		next_state = STATE_IDLE;
	end
	endcase
end

localparam last_addr = 16'hfffe;

always @(*) begin
	case (state)
	STATE_READ: h_bytesel = h_compl ? 2'b00 : 2'b11;
	STATE_WRITE: h_bytesel = h_compl ? 2'b00 : 2'b11;
	default: h_bytesel = 2'b00;
	endcase
end

always @(posedge clk) begin
	if (state == STATE_INC) begin
		h_addr <= h_addr[15:0] == last_addr ?
			32'd0 : h_addr + 32'd2;
		if (h_addr[15:0] == last_addr && !write_done) begin
			$display("test pattern: %s", pattern_sel ? "aa55/55aa" : "address + 1");
			$display("%f finished writing", $time);
			write_done <= 1'b1;
		end else if (h_addr[15:0] == last_addr) begin
			$display("%f write+read test passed", $time);
			write_done <= 1'b0;
			pattern_sel <= 1'b1;
			if (pattern_sel)
				$finish;
		end
	end
end

always @(posedge clk)
	state <= next_state;

endmodule
