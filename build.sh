sudo meson build --wipe
cd build/
sudo ninja
sudo ninja install
cd ../
sudo lightdm stop
sudo lightdm start
