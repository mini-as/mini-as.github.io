@echo off
echo ---- build bootloader --------
as boot.asm minis.img
echo.
echo ---- build kernel ------------
as kernel.asm kernel
echo.
echo ---- build system ------------
imgmount a minis.img -t floppy
copy kernel A:\
echo.
