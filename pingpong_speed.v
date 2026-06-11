library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ping_pong is
    Port ( 
        i_clk, i_rst   : in  STD_LOGIC;
        i_btnL, i_btnR : in  STD_LOGIC;
        o_led          : out STD_LOGIC_VECTOR (7 downto 0)
    );
end ping_pong;

architecture Behavioral of ping_pong is

    type t_state is (wait_serve, serve_L, serve_R, play, check_win, win_R, win_L); 
    constant bits : integer := 25; 

    signal state      : t_state;
    signal led        : STD_LOGIC_VECTOR(7 downto 0);
    signal dir        : STD_LOGIC; 
    signal sc_L       : STD_LOGIC_VECTOR(3 downto 0);
    signal sc_R       : STD_LOGIC_VECTOR(3 downto 0);
    signal cnt        : STD_LOGIC_VECTOR(bits-1 downto 0) := (others => '0');
    signal f_clk      : std_logic;
    
    signal btnL_reg, btnR_reg       : std_logic;
    signal btnL_pulse, btnR_pulse   : std_logic;
    signal lfsr        : STD_LOGIC_VECTOR(3 downto 0) := "1011"; -- 非零種子
    signal speed_top   : STD_LOGIC_VECTOR(2 downto 0) := "100";  -- 預設中速
    signal speed_cnt   : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal move_tick   : STD_LOGIC;  -- '1' 代表本週期球需移動一格

begin

    o_led <= led;

    -- 1. 除頻器
    frequencydivider: process(i_clk, i_rst)
    begin
        if i_rst = '1' then 
            cnt <= (others => '0');
        elsif rising_edge(i_clk) then 
            cnt <= cnt + 1;
        end if;
    end process;
    f_clk <= cnt(bits-1);


    -- 2. 按鍵暫存器 (邊緣觸發偵測)
    p_btn: process(f_clk, i_rst)
    begin
        if i_rst = '1' then
            btnL_reg <= '0';
            btnR_reg <= '0';
        elsif rising_edge(f_clk) then
            btnL_reg <= i_btnL;
            btnR_reg <= i_btnR;
        end if;
    end process;
    btnL_pulse <= '1' when (i_btnL = '1' and btnL_reg = '0') else '0';
    btnR_pulse <= '1' when (i_btnR = '1' and btnR_reg = '0') else '0';


    -- 3a. LFSR 亂數產生器
    p_lfsr: process(f_clk, i_rst)
    begin
        if i_rst = '1' then
            lfsr      <= "1011";
            speed_top <= "100";
        elsif rising_edge(f_clk) then
            -- 觸發條件：進入 serve_L/serve_R 的那一拍，或擊球成功的那一拍，或球移動的那一拍
            if (state = wait_serve and (btnL_pulse = '1' or btnR_pulse = '1')) or
               (state = play and ((led = "10000000" and btnL_pulse = '1') or (led = "00000001" and btnR_pulse = '1'))) or
               (move_tick = '1') then
                lfsr(3) <= lfsr(0);
                lfsr(2) <= lfsr(3) xor lfsr(0);  -- tap
                lfsr(1) <= lfsr(2);
                lfsr(0) <= lfsr(1);
                if lfsr(2 downto 0) = "000" then
                    speed_top <= "111";  -- 8 ticks（最慢）
                else
                    speed_top <= lfsr(2 downto 0);  -- 1~7 ticks
                end if;
            end if;
        end if;
    end process;


    -- 3b. 變速計數器
    -- 累計到 speed_top 才產生一個 move_tick
    p_speed: process(f_clk, i_rst)
    begin
        if i_rst = '1' then
            speed_cnt <= (others => '0');
        elsif rising_edge(f_clk) then
            if state /= play then
                speed_cnt <= (others => '0');  -- 非 play 狀態重置
            elsif speed_cnt >= speed_top then
                speed_cnt <= (others => '0');
            else
                speed_cnt <= speed_cnt + 1;
            end if;
        end if;
    end process;
    move_tick <= '1' when (state = play and speed_cnt = speed_top) else '0';


    -- 4. 主狀態機
    FSM: process(f_clk, i_rst)
    begin
        if i_rst = '1' then
            state <= wait_serve;
        elsif rising_edge(f_clk) then
            case state is
                when wait_serve =>
                    if btnL_pulse = '1' then    state <= serve_L; 
                    elsif btnR_pulse = '1' then state <= serve_R; 
                    end if;
                when serve_L | serve_R =>
                    state <= play;
                when play =>    
                    if (dir = '1' and led = "10000000" and btnL_pulse = '0') or (led /= "10000000" and btnL_pulse = '1') then
                        state <= check_win;
                    elsif (dir = '0' and led = "00000001" and btnR_pulse = '0') or (led /= "00000001" and btnR_pulse = '1') then
                        state <= check_win;
                    end if;
                when check_win =>
                    if sc_L = "1111" then    state <= win_L;
                    elsif sc_R = "1111" then state <= win_R;
                    else                     state <= wait_serve; 
                    end if;
                when win_L | win_R =>
                    state <= state; 
                when others =>  
                    state <= wait_serve;
            end case;
        end if;
    end process;


    -- 5. LED 燈光控制（play 狀態改用 move_tick 驅動移動）
    p_led: process(f_clk, i_rst)
    begin
        if i_rst = '1' then led <= "00000000";
        elsif rising_edge(f_clk) then
            case state is
                when wait_serve | check_win | win_L | win_R => 
                    led <= sc_L & sc_R; 
                    
                when serve_L =>
                    led <= "10000000"; 
                when serve_R =>
                    led <= "00000001"; 
                    
                when play =>
                    if led = "10000000" and btnL_pulse = '1' then
                        led <= "01000000";  -- 擊球後立刻移動，不等 tick
                    elsif led = "00000001" and btnR_pulse = '1' then
                        led <= "00000010";
                    -- ↓ 只有在 move_tick 時才讓球自動前進
                    elsif move_tick = '1' then
                        if dir = '0' then led <= '0' & led(7 downto 1); 
                        else              led <= led(6 downto 0) & '0'; 
                        end if;
                    end if;
                    
                when others => 
                    led <= (others => '0');
            end case;
        end if;
    end process;


    -- 6. 球的移動方向控制
    p_dir: process(f_clk, i_rst)
    begin
        if i_rst = '1' then dir <= '0';
        elsif rising_edge(f_clk) then
            if state = serve_L then 
                dir <= '0';
            elsif state = serve_R then 
                dir <= '1';
            elsif state = play then
                if led = "10000000" and btnL_pulse = '1' then      dir <= '0'; 
                elsif led = "00000001" and btnR_pulse = '1' then   dir <= '1'; 
                end if;
            end if;
        end if;
    end process;


    -- 7. 計分控制
    p_score: process(f_clk, i_rst)
    begin
        if i_rst = '1' then 
            sc_L <= "0000";
            sc_R <= "0000";
        elsif rising_edge(f_clk) then
            if state = play then
                if (dir = '1' and led = "10000000" and btnL_pulse = '0') or (led /= "10000000" and btnL_pulse = '1') then
                    sc_R <= sc_R + 1;
                elsif (dir = '0' and led = "00000001" and btnR_pulse = '0') or (led /= "00000001" and btnR_pulse = '1') then
                    sc_L <= sc_L + 1;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
