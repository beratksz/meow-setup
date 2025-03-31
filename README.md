chmod +x meow-backup.sh
chmod +x meow-restore.sh
chmod +x meow-setup.sh

rclone yapılandırılma sırasında eğer sunucudan tarayıca açılmıyorsa tarayıcı açılan bir yerden rclone kurup yapılandırılan config dosyasını sunucudaki rclone config ile değiştirin


cronjob

0 3 * * * /bin/bash /home/<kullanici-adi>/meow-setup/<your_script>.sh >> /home/<kullanici-adi>/meow-setup/cron.log 2>&1
