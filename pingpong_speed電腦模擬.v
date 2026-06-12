library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_ping_pong is
-- Testbench 不需要定義 Port
end tb_ping_pong;

architecture behavior of tb_ping_pong is

    -- 宣告待測模組 (UUT)
    component ping_pong
    Port ( 
        i_clk   : in  STD_LOGIC;
        i_rst   : in  STD_LOGIC;
        i_btnL  : in  STD_LOGIC;
        i_btnR  : in  STD_LOGIC;
        o_led   : out STD_LOGIC_VECTOR (7 downto 0)
    );
    end component;

    -- 宣告連接待測模組的訊號
    signal i_clk   : STD_LOGIC := '0';
    signal i_rst   : STD_LOGIC := '0';
    signal i_btnL  : STD_LOGIC := '0';
    signal i_btnR  : STD_LOGIC := '0';
    signal o_led   : STD_LOGIC_VECTOR (7 downto 0);


    constant clk_period : time := 10 ns;

begin


    uut: ping_pong PORT MAP (
        i_clk   => i_clk,
        i_rst   => i_rst,
        i_btnL  => i_btnL,
        i_btnR  => i_btnR,
        o_led   => o_led
    );

    clk_process :process
    begin
        i_clk <= '0';
        wait for clk_period/2;
        i_clk <= '1';
        wait for clk_period/2;
    end process;


    stim_proc: process
    begin		
        i_rst <= '1';
        wait for 100 ns;	
        i_rst <= '0';
        wait for 100 ns;
        i_btnL <= '1';
        wait for 100 ns; 
        i_btnL <= '0';
        wait for 500 ns; 

        -- 3. 右方玩家回擊 (Press R)
        i_btnR <= '1';
        wait for 100 ns;
        i_btnR <= '0';

        -- 等待球往左飛一段時間
        wait for 800 ns;

        -- 4. 模擬左方玩家漏接 (不按按鈕) 或是過早按按鈕
        -- 過早按按鈕導致失誤
        i_btnL <= '1';
        wait for 100 ns;
        i_btnL <= '0';

        -- 讓模擬繼續跑一段時間觀察計分 (o_led 顯示分數) 狀態
        wait for 2 us;

        -- 5. 新的一局，右方玩家發球
        i_btnR <= '1';
        wait for 100 ns;
        i_btnR <= '0';
        
        wait for 1 us;

        report "Simulation Finished" severity note;
        wait;
    end process;

end behavior;