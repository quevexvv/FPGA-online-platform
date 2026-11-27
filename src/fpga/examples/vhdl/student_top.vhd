library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity student_top is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        din   : in  std_logic_vector(9 downto 0);
        dout  : out std_logic_vector(17 downto 0)
    );
end entity;

architecture rtl of student_top is
    signal count : unsigned(17 downto 0) := (others => '0');
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count <= (others => '0');
            else
                count <= count + resize(unsigned(din), count'length);
            end if;
        end if;
    end process;
    dout <= std_logic_vector(count);
end architecture;
