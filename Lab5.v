module Lab5 (
    input  wire clk,
    input  wire S1, S2,
    output wire X, Y,
    output reg  buzzer = 1'b1
);

reg [7:0] x = 128, y = 60;
reg [9:0] sx = 0, sy = 0;
reg [10:0] timer = 0;
reg [2:0] phase = 0;       // 0=T, 1=O, 2=N, 3=E, 4=Star
reg [3:0] segment = 0;
reg [6:0] t = 0;

// Button synchronization
reg s1a = 1, s1b = 1;
reg s2a = 1, s2b = 1;

// Debounce
reg [18:0] db1 = 0, db2 = 0;
reg k1 = 1, k2 = 1;
reg prev1 = 1, prev2 = 1;

// Beep: 2 kHz for 80 ms
reg [13:0] tone_count = 0;
reg [21:0] beep_count = 0;

// Coordinates: {x0, y0, x1, y1}
// Every path ends where it starts, so no return trace appears.
function [31:0] shape;
    input [2:0] p;
    input [3:0] s;
    begin
        shape = {8'd128,8'd60,8'd128,8'd60};
        case (p)
        // T
        0: case(s)
            0: shape={8'd128,8'd60,8'd128,8'd210};   // stem up
            1: shape={8'd128,8'd210,8'd80,8'd210};   // bar to left
            2: shape={8'd80,8'd210,8'd176,8'd210};   // bar to right
            3: shape={8'd176,8'd210,8'd128,8'd210};  // back to center
            4: shape={8'd128,8'd210,8'd128,8'd60};   // stem down
        endcase
        // O
        1: case(s)
            0: shape={8'd100,8'd60,8'd150,8'd60};
            1: shape={8'd150,8'd60,8'd170,8'd90};
            2: shape={8'd170,8'd90,8'd170,8'd180};
            3: shape={8'd170,8'd180,8'd150,8'd210};
            4: shape={8'd150,8'd210,8'd100,8'd210};
            5: shape={8'd100,8'd210,8'd80,8'd180};
            6: shape={8'd80,8'd180,8'd80,8'd90};
            7: shape={8'd80,8'd90,8'd100,8'd60};
        endcase
        // N
        2: case(s)
            0: shape={8'd85,8'd60,8'd85,8'd210};     // left stroke up
            1: shape={8'd85,8'd210,8'd165,8'd60};    // diagonal down
            2: shape={8'd165,8'd60,8'd165,8'd210};   // right stroke up
            3: shape={8'd165,8'd210,8'd165,8'd60};   // retrace right
            4: shape={8'd165,8'd60,8'd85,8'd210};    // retrace diagonal
            5: shape={8'd85,8'd210,8'd85,8'd60};     // retrace left
        endcase
        // E
        3: case(s)
            0: shape={8'd165,8'd60,8'd90,8'd60};     // bottom bar
            1: shape={8'd90,8'd60,8'd90,8'd135};     // spine to middle
            2: shape={8'd90,8'd135,8'd150,8'd135};   // middle bar
            3: shape={8'd150,8'd135,8'd90,8'd135};   // back
            4: shape={8'd90,8'd135,8'd90,8'd210};    // spine to top
            5: shape={8'd90,8'd210,8'd165,8'd210};   // top bar
            6: shape={8'd165,8'd210,8'd90,8'd210};   // back
            7: shape={8'd90,8'd210,8'd90,8'd60};     // spine down
            8: shape={8'd90,8'd60,8'd165,8'd60};     // bottom bar again
        endcase
        // Star (pentagram, closed path)
        4: case(s)
            0: shape={8'd128,8'd210,8'd84,8'd74};
            1: shape={8'd84,8'd74,8'd199,8'd158};
            2: shape={8'd199,8'd158,8'd57,8'd158};
            3: shape={8'd57,8'd158,8'd172,8'd74};
            4: shape={8'd172,8'd74,8'd128,8'd210};
        endcase
        endcase
    end
endfunction

reg [3:0] last_segment;
always @(*) begin
    case (phase)
        0: last_segment = 4;   // T
        1: last_segment = 7;   // O
        2: last_segment = 5;   // N
        3: last_segment = 8;   // E
        4: last_segment = 4;   // Star
        default: last_segment = 0;
    endcase
end

wire [31:0] v = shape(phase, segment);
wire [7:0] x0 = v[31:24];
wire [7:0] y0 = v[23:16];
wire [7:0] x1 = v[15:8];
wire [7:0] y1 = v[7:0];

wire signed [10:0] dx =
    $signed({1'b0,x1}) - $signed({1'b0,x0});
wire signed [10:0] dy =
    $signed({1'b0,y1}) - $signed({1'b0,y0});
wire signed [20:0] ix =
    $signed({1'b0,x0}) +
    (dx * $signed({1'b0,t})) / 63;
wire signed [20:0] iy =
    $signed({1'b0,y0}) +
    (dy * $signed({1'b0,t})) / 63;

wire press1 = prev1 && !k1;
wire press2 = prev2 && !k2;

always @(posedge clk) begin
    // Synchronize buttons
    s1a <= S1;
    s1b <= s1a;
    s2a <= S2;
    s2b <= s2a;

    // Debounce: approximately 10 ms
    if (s1b == k1)
        db1 <= 0;
    else if (db1 == 499999) begin
        db1 <= 0;
        k1 <= s1b;
    end else
        db1 <= db1 + 1'b1;

    if (s2b == k2)
        db2 <= 0;
    else if (db2 == 499999) begin
        db2 <= 0;
        k2 <= s2b;
    end else
        db2 <= db2 + 1'b1;

    prev1 <= k1;
    prev2 <= k2;

    // Working sigma-delta DAC
    sx <= {2'b00,sx[7:0]} + {2'b00,x};
    sy <= {2'b00,sy[7:0]} + {2'b00,y};

    // Button selection
    if (press1 || press2) begin
        if (press1)
            phase <= (phase == 4) ? 0 : phase + 1'b1;
        else
            phase <= (phase == 0) ? 4 : phase - 1'b1;

        segment <= 0;
        t <= 0;
        timer <= 0;

        // Start beep
        beep_count <= 4000000;
        tone_count <= 0;
        buzzer <= 1'b1;
    end else begin
        // Drawing engine
        if (timer == 1388) begin
            timer <= 0;
            x <= ix[7:0];
            y <= iy[7:0];
            if (t == 63) begin
                t <= 0;
                segment <= (segment == last_segment) ?
                           0 : segment + 1'b1;
            end else
                t <= t + 1'b1;
        end else
            timer <= timer + 1'b1;

        // Buzzer oscillator
        if (beep_count != 0) begin
            beep_count <= beep_count - 1'b1;
            if (tone_count == 12499) begin
                tone_count <= 0;
                buzzer <= ~buzzer;
            end else
                tone_count <= tone_count + 1'b1;
        end else begin
            // Inactive buzzer = HIGH
            buzzer <= 1'b1;
            tone_count <= 0;
        end
    end
end

assign X = sx[8];
assign Y = sy[8];
endmodule