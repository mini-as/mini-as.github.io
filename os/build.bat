@echo off
echo ---- build bootloader --------
as boot.asm minis.img
echo.
echo ---- build kernel ------------
as kernel.asm kernel
echo.
echo ---- build system ------------
imdisk -a -s 180k -o fd -f minis.img -m A:
move kernel A:\
timeout 3
echo.
imdisk -D -m A:
echo.
pause