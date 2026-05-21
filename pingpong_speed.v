library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ping_pong is
    generic (
        G_BASE_SPEED : integer := 5000000; -- 最快極限
        G_SPEED_MULT : integer := 50000;   -- 隨機變速的落差倍率
        G_MAX_COUNT  : integer := 20000000 -- 計數器最大容量
    );
    Port ( 
        i_clk, i_rst   : in  STD_LOGIC;
        i_btnL, i_btnR : in  STD_LOGIC;
        i_btn_next     : in  STD_LOGIC; 
        o_led          : out STD_LOGIC_VECTOR (7 downto 0)
    );
end ping_pong;

architecture Behavioral of ping_pong is

    type t_state is (wait_serve, serve_L, serve_R, play, show_score, win_R, win_L); 

    signal state      : t_state;
    signal led        : STD_LOGIC_VECTOR(7 downto 0);
    signal dir        : STD_LOGIC; 
    signal sc_L       : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    signal sc_R       : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    signal last_winner: std_logic := '0'; 

    -- ==========================================
    -- 變速節拍器 (Tick) 與 亂數產生器 (LFSR)
    -- ==========================================
    signal cnt        : integer range 0 to G_MAX_COUNT := 0; 
    signal threshold  : integer range 0 to G_MAX_COUNT := G_BASE_SPEED; 
    signal move_tick  : std_logic := '0'; -- 業界標準：移動致能脈衝

    signal lfsr_reg   : STD_LOGIC_VECTOR(7 downto 0) := x"5A"; 
    signal feedback   : STD_LOGIC;

begin

    o_led <= led;

    -- 1. LFSR 亂數產生器 (維持 100MHz 狂飆)
    feedback <= lfsr_reg(7) xor lfsr_reg(5) xor lfsr_reg(4) xor lfsr_reg(3);
    proc_lfsr: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            lfsr_reg <= x"5A";
        elsif rising_edge(i_clk) then
            lfsr_reg <= lfsr_reg(6 downto 0) & feedback;
        end if;
    end process;


    -- 2. 隨機變速節拍器 (Tick Generator)
    proc_tick_gen: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            cnt <= 0;
            move_tick <= '0';
            threshold <= G_BASE_SPEED;
        elsif rising_edge(i_clk) then
            -- 預設為 0，確保脈衝只有短短的一個 Clock
            move_tick <= '0'; 
            
            if cnt >= threshold then
                cnt <= 0;
                move_tick <= '1'; -- 時間到！發出移動指令
                
                -- 【變速核心】球移動的瞬間，立刻抓取新亂數，決定下一步要走多慢
                threshold <= G_BASE_SPEED + (conv_integer(lfsr_reg) * G_SPEED_MULT);
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;


    -- ==========================================
    -- 所有遊戲邏輯全部吃 i_clk，實現零延遲按鈕
    -- ==========================================

    -- 3. 主狀態機
    proc_fsm: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            state <= wait_serve;
        elsif rising_edge(i_clk) then
            case state is
                when wait_serve =>
                    if i_btnL = '1' or i_btnR = '1' then state <= play; end if;
                when serve_L =>
                    if i_btnL = '1' then state <= play; end if;
                when serve_R =>
                    if i_btnR = '1' then state <= play; end if;
                    
                when play =>    
                    -- 【重點】遊玩時，只有收到 move_tick 指令的瞬間，才判定有沒有漏接或犯規
                    if move_tick = '1' then
                        if dir = '1' then  
                            if (led = "10000000" and i_btnL = '0') or (led /= "10000000" and i_btnL = '1') then
                                state <= show_score;
                            end if;
                        else               
                            if (led = "00000001" and i_btnR = '0') or (led /= "00000001" and i_btnR = '1') then
                                state <= show_score;
                            end if;
                        end if;
                    end if;
                    
                when show_score =>
                    if i_btn_next = '1' then
                        if sc_L = "1111" then    state <= win_L;
                        elsif sc_R = "1111" then state <= win_R;
                        else
                            if last_winner = '0' then state <= serve_L;
                            else                      state <= serve_R;
                            end if;
                        end if;
                    end if;
                when win_L | win_R =>
                    state <= state; 
                when others =>  
                    state <= wait_serve;
            end case;
        end if;
    end process;

    -- 4. LED 燈光控制
    proc_led: process(i_clk, i_rst)
    begin
        if i_rst = '1' then led <= "10000001";
        elsif rising_edge(i_clk) then
            case state is
                when wait_serve => led <= "10000001"; 
                when serve_L =>    led <= "10000000"; 
                when serve_R =>    led <= "00000001"; 
                when play =>
                    -- 【重點】球只在收到 move_tick 指令時才會移動！
                    if move_tick = '1' then
                        if led = "10000000" and i_btnL = '1' then      led <= "01000000";
                        elsif led = "00000001" and i_btnR = '1' then   led <= "00000010";
                        else
                            if dir = '0' then led <= '0' & led(7 downto 1); 
                            else              led <= led(6 downto 0) & '0'; 
                            end if;
                        end if;
                    end if;
                when show_score | win_L | win_R => led <= sc_L & sc_R; 
                when others => led <= (others => '0');
            end case;
        end if;
    end process;

    -- 5. 球的方向控制
    proc_dir: process(i_clk, i_rst)
    begin
        if i_rst = '1' then dir <= '0';
        elsif rising_edge(i_clk) then
            if state = wait_serve then
                if i_btnL = '1' then     dir <= '0'; 
                elsif i_btnR = '1' then  dir <= '1'; 
                end if;
            elsif state = serve_L then
                if i_btnL = '1' then dir <= '0'; end if; 
            elsif state = serve_R then
                if i_btnR = '1' then dir <= '1'; end if; 
            elsif state = play then
                if move_tick = '1' then
                    if led = "10000000" and i_btnL = '1' then      dir <= '0'; 
                    elsif led = "00000001" and i_btnR = '1' then   dir <= '1'; 
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- 6. 雙方計分
    proc_score: process(i_clk, i_rst)
    begin
        if i_rst = '1' then 
            sc_L <= "0000";
            sc_R <= "0000";
            last_winner <= '0';
        elsif rising_edge(i_clk) then
            if state = play then
                if move_tick = '1' then
                    if dir = '0' then
                        if (led = "00000001" and i_btnR = '0') or (led /= "00000001" and i_btnR = '1') then
                            sc_L <= sc_L + 1; last_winner <= '0'; 
                        end if;
                    elsif dir = '1' then
                        if (led = "10000000" and i_btnL = '0') or (led /= "10000000" and i_btnL = '1') then
                            sc_R <= sc_R + 1; last_winner <= '1'; 
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;