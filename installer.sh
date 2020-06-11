#!/bin/bash

# Check if this is being installed as root or not
if [ "$EUID" -ne 0 ]
    then
        # Set HISTIGNORE to ignore piped-password-sudo commands to protect the sudo password from being stored in plaintext in logs
        export HISTIGNORE='*sudo -S*'
        read -srp "Please enter sudo password: " sudoPW
fi

# Warn users that this installation script is assumption-heavy
printf "\n*************\n[WARNING] - This installation script makes a lot of assumptions and you may encounter errors.\n*************\n\n"

# Check for sufficient disk space
diskUsage=$(df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 }' | grep root | awk '{ print $1}' | cut -d '%' -f1)
if [[ $diskUsage -ge 90 ]]
    then
        read -rp "Disk 90% or more full, would you like to try the installation anyways [y/N]?" diskWarn
        if [ "$diskWarn" != "y" ]
            then
                echo "Cancelling installation..."
                exit 0
        fi
fi

# Check for compatible OS
distroCheck=$(lsb_release -irdc | head -n 1 | awk '{print $3}')
versionCheck=$(lsb_release -irdc | head -n 3 | tail -n 1 | awk '{print $2}')
if [ "$distroCheck" != "Raspbian" ]
    then
        echo "OS is incompatible, required OS: Raspbian / RaspberryOS"
        exit 1
    else
        if [[ $versionCheck -lt 10 ]]
            then
                echo "OS Version is less than 10 (Buster), you may encounter incompatibilities"
                read -rp "Would you like to proceed anyways [y/N]?" osVersion
                if [ "$osVersion" != "y" ]
                    then
                        echo "Cancelling installation..."
                        exit 1
                    else
                        echo "Proceeding with installation..."
                fi
        fi
fi

# Setup passwordless sudo for killall & tee so that vlooper can start/stop omxplayer w/o needing a sudo password everytime
## First check if this is being installed as root or not
if [ "$EUID" -ne 0 ]
    then
        echo "Setting up sudo exemption for vlooper script to stop services"
        touch ./examples/vlooper-exception
        echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/killall,/usr/bin/tee" > ./examples/vlooper-exception
        echo "$sudoPW" | sudo -S -k chown root:root ./examples/vlooper-exception
        echo "$sudoPW" | sudo -S -k mv ./examples/vlooper-exception /etc/sudoers.d/
fi

# Prompt user how they want to import their new videos to the vlooper service
read -rp "Would you like to retrieve your new videos from a remote file share such as SMB or NFS [y/N]?" mediaMethod
if [[ "$mediaMethod" = "y" ]]
    then
        read -rp "Would you like to use SMB or NFS [smb/nfs]?" remoteMethod
    else
        echo "In order to play new videos automatically, you will need to upload them into this folder: /mnt/tvMedia"
fi

# Check for dependencies and ask to install them if unmet
echo "Checking dependencies..."
declare -a packages=("omxplayer")
if [[ "$mediaMethod" = "y" ]]
    then
        if [[ "$remoteMethod" = "smb" ]]
            then
                packages+=("cifs-utils")
            else
                packages+=("nfs-common")
        fi
fi
for package in "${packages[@]}"; do
    pkgInstalled=$(dpkg --get-selections | grep "$package" | awk '{print $1}')
    if [[ -z $pkgInstalled ]]
        then
            read -rp "$package not installed, install [y/N]?" doInstall
            if [[ "$doInstall" = "y" ]]
                then
                    echo "Installing $package..."
                    if [ "$EUID" -ne 0 ]
                        then
                            if ! echo "$sudoPW" | sudo -S -k apt install "$package" -y > /dev/null 2>&1
                                then
                                    echo "Failed to install $package! Aborting installation..."
                                    exit 1
                                else
                                    echo "Installed $package!"
                            fi
                        else
                            if ! apt install "$package" -y > /dev/null 2>&1
                                then
                                    echo "Failed to install $package! Aborting installation..."
                                    exit 1
                                else
                                    echo "Installed $package!"
                            fi
                    fi
                else
                    echo "Not installing $package, aborting installation"
                    exit 1
            fi
    fi
done
echo "Dependencies met! Installing Video Looper now..."

# Update the main.cfg file for usage
echo "Building configuration file..."
read -rp "What file name will your new videos be titled (ex. announcements.mp4)?" newFile
read -rp "What file name will your playing video be titled (ex. announcement.mp4)?" playFile
if ! sed -i'' -e "s,# fileOwner=,fileOwner=$USER,ig" -e "s,# baseDir=,baseDir=$HOME/vlooper,ig" -e "s,newVideo=\"announcements.mp4\",newVideo=\"$newFile\",ig" -e "s,curVideo=\"announcement.mp4\",curVideo=\"$playFile\",g" ./examples/main.example
    then
        echo "Failed to build configuration file, aborting installation!"
        exit 1
fi

# Update the vlogroate conf file for usage
if ! sed -i'' -e "s,create 660,create 660 $USER $USER,g" ./examples/vlogrotate.example
    then
        echo "Failed to build vlogroate configuration file, aborting installation!"
        exit 1
fi

# Create all the directories for the script to be installed in
echo "Creating directories..."
if ! mkdir -p ~/vlooper/inc
    then
        echo "Failed to create directories"
        exit 1
fi
if ! mkdir -p ~/vlooper/video
    then
        echo "Failed to create directories"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k mkdir -p /mnt/tvMedia 2>&1
            then
                echo "Failed to create /mnt/tvMedia for remoteFS mount, aborting installation!"
                exit 1
        fi
    else
        if ! mkdir -p /mnt/tvMedia 2>&1
            then
                echo "Failed to create /mnt/tvMedia for remoteFS mount, aborting installation!"
                exit 1
        fi
fi

# Setup the users desired remote media method
# Check if the user wants to connect to a remote FS such as SMB or NFS
if [[ "$mediaMethod" = "y" ]]
    then
        # Check if the user wants to use SMB or NFS
        if [[ "$remoteMethod" = "smb" ]]
            then
                read -rp "What is the filepath for the SMB share you wish to mount (Ex. //192.168.0.1/TvMedia)?" smbShare
                read -rp "What username should be used to connect to the SMB Share (leave blank for none)?" smbUser
                if [[ -n "$smbUser" ]]
                    then
                        read -rp "What password should be used to connect to the SMB Share?" smbPass
                        read -rp "What domain should be used to connect to the SMB Share (leave blank for none)?" smbDomain
                        # Create the SMB credential file
                        if ! touch ~/.smbCreds 2>&1
                            then
                                echo "Failed to create SMB credential file, aborting installation!"
                                exit 1
                        fi
                        # Setup SMB credential file permissions
                        if ! chmod 600 ~/.smbCreds 2>&1
                            then
                                echo "Failed to secure SMB credential file, please secure manually with: chmod 600 ~/.smbCreds"
                        fi
                        # Setup the SMB credential file
                        if ! echo "user=$smbUser" >> ~/.smbCreds
                            then
                                echo "Failed to set SMB User, please manually set 'user=$smbUser' with: nano ~/.smbCreds"
                        fi
                        if ! echo "password=$smbPass" >> ~/.smbCreds
                            then
                                echo "Failed to set SMB Password, please manually set 'password=$smbPass' with: nano ~/.smbCreds"
                        fi
                        if [[ -n "$smbDomain" ]]
                            then
                                if ! echo "domain=$smbDomain" >> ~/.smbCreds
                                    then
                                        echo "Failed to set SMB Domain, please manually set 'domain=$smbDomain' with: nano ~/.smbCreds"
                                fi
                        fi
                fi
                # Setup the SMB connection
                if [[ -n "$smbUser" ]]
                    then
                        if ! echo "$sudoPW" | sudo -S -k echo "$smbShare    /mnt/tvMedia  cifs    uid=$USER,gid=$USER,credentials=$HOME/.smbCreds,iocharset=utf8,rw 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo "Failed to add SMB Mount to /etc/fstab"
                                exit 1
                        fi
                    else
                        if ! echo "$sudoPW" | sudo -S -k echo "$smbShare    /mnt/tvMedia  cifs    uid=$USER,gid=$USER,iocharset=utf8,rw 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo "Failed to add SMB Mount to /etc/fstab"
                                exit 1
                        fi
                fi
            else
                # Setup the NFS connection
                read -rp "What is the filepath for the NFS share you wish to mount (Ex. 192.168.0.1:/TvMedia)?" nfsShare
                read -rp "What username should be used to connect to the NFS Share (leave blank for none)?" nfsUser
                if [[ -n "$nfsUser" ]]
                    then
                        read -rp "What password should be used to connect to the NFS Share?" nfsPass
                        if ! echo "$sudoPW" | sudo -S -k echo "$nfsShare    /mnt/tvMedia  nfs    username=$nfsUser,password=$nfsPass,rw,noexec,nosuid 0 0" | sudo tee -a /etc/fstab > /dev/null /2>&1
                            then
                                echo "Failed to add NFS Mount to /etc/fstab"
                                exit 1
                        fi
                    else
                        if ! echo "$sudoPW" | sudo -S -k echo "$nfsShare    /mnt/tvMedia  nfs    rw,noexec,nosuid 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo "Failed to add NFS Mount to /etc/fstab"
                                exit 1
                        fi
                fi
        fi
        # Mount the remote file share
        if ! echo "$sudoPW" | sudo -S -k mount -a
            then
                echo "Failed to mount the remote file share, please check /etc/fstab for errors!"
                exit 1
        fi
    else
        # Update main.cfg to comment network var, and set it to true to pass future checks.
        if ! sed -i'' -e "s,#smbResult=\"true\",smbResult=\"true\",ig" -e "s,smbResult=\$(,#smbResult=\$(,g" ./examples/main.example
            then
                echo "Failed to update main.cfg with network parameters, aborting installation!"
                exit 1
        fi
fi

# Install the files into those directories
echo "Installing files into directories..."
if ! cp ./examples/vlooper.example ~/vlooper/vlooper.sh && chmod +x ~/vlooper/vlooper.sh
    then
        echo "Failed to install vlooper script and make executable"
        exit 1
fi
if ! cp ./examples/vlooper_boot.example ~/vlooper/vlooper_boot.sh && chmod +x ~/vlooper/vlooper_boot.sh
    then
        echo "Failed to install vlooper_boot script and make executable"
        exit 1
fi
if ! cp ./examples/vupdate.example ~/vlooper/vupdate.sh && chmod +x ~/vlooper/vupdate.sh
    then
        echo "Failed to install vupdate script and make executable"
        exit 1
fi
if ! cp ./examples/main.example ~/vlooper/inc/main.cfg && chmod +x ~/vlooper/inc/main.cfg
    then
        echo "Failed to install configuration file and make executable"
        exit 1
fi
if ! cp ./examples/announcement.mp4 "$HOME/vlooper/video/$playFile"
    then
        echo "Failed to install demo video file"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper
            then
                echo "Failed to create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k touch /var/log/vlooper.log
            then
                echo "Failed to create /var/log/vlooper.log"
                exit 1
            else
                if ! echo "$sudoPW" | sudo -S -k chown "$USER":"$USER" /var/log/vlooper.log
                    then
                        echo "Failed to update ownerships of /var/log/vlooper.log, please run: sudo chown $USER:$USER /var/log/vlooper.log"
                fi
        fi
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service
            then
                echo "Failed to install omxlooper service"
                exit 1
        fi
    else
        if ! cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper
            then
                echo "Failed to create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! touch /var/log/vlooper.log
            then
                echo "Failed to create /var/log/vlooper.log"
                exit 1
        fi
        if ! cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service
            then
                echo "Failed to install omxlooper service"
                exit 1
        fi
fi

# Make symlink to vupdate script
if [ "$EUID" -ne 0 ]
    then
        echo "Creating symbolic link to vupdate script... You can invoke this script simply be typing: vupdate"
        if ! echo "$sudoPW" | sudo -S -k ln -s "$HOME/vlooper/vupdate.sh" /usr/bin/vupdate
            then
                echo "Failed to create vupdate symlink, you can optionally create this if you choose so"
            fi
        echo "Creating symbolic link to vlooper script... You can invoke this script simply be typing: vlooper {start|stop|restart}"
        if ! echo "$sudoPW" | sudo -S -k ln -s "$HOME/vlooper/vlooper.sh" /usr/bin/vlooper
            then
                echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
                echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
        fi
        echo "Creating symbolic link to vloop_boot script..."
        if ! echo "$sudoPW" | sudo -S -k ln -s "$HOME/vlooper/vlooper_boot.sh" /usr/bin/vlooper_boot
            then
                echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
                echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
        fi
    else
        echo "Creating symbolic link to vupdate script... You can invoke this script simply be typing: vupdate"
        if ! ln -s ~/vlooper/vupdate.sh /usr/bin/vupdate
            then
                echo "Failed to create vupdate symlink, you can optionally create this if you choose so"
            fi
        echo "Creating symbolic link to vlooper script... You can invoke this script simply be typing: vlooper {start|stop|restart}"
        if ! ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper
            then
                echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
                echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
        fi
        echo "Creating symbolic link to vloop_boot script..."
        if ! ln -s ~/vlooper/vlooper_boot.sh /usr/bin/vlooper_boot
            then
                echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
                echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
        fi
fi

# Setup crontab
echo "Setting up crontab to run vupdate every minute"
if ! crontab -l | { cat; echo "* * * * * /usr/bin/vlooper"; } | crontab -
    then
        echo "Failed to install cronjob to check for new media every minute"
        exit 1
fi

# Setup omxLooper service so the video loop starts on boot and stays alive
echo "Installing omxLooper service..."
if ! sed -i'' -e "s,WorkingDirectory=,WorkingDirectory=$HOME/vlooper,ig" ./examples/omxlooper.example
    then
        echo "Failed to build omxLooper service file, aborting installation!"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service
            then
                echo "Failed to install omxlooper as a service, this is important if you want the video to loop automatically on boot after powerloss"
                echo "Please remedy manually by referencing ./examples/omxlooper.example and installing that file into /etc/systemd/system/omxlooper.service"
        fi
        if ! echo "$sudoPW" | sudo -S -k systemctl start omxlooper.service
            then
                echo "Failed to start omxlooper service!"
                echo "Please investigate via sudo systemctl status omxlooper.service or log files"
            else
                echo "Started omxlooper service!"
        fi
        if ! echo "$sudoPW" | sudo -S -k systemctl enable omxlooper.service
            then
                echo "Failed to enable omxlooper service!"
                echo "Please investigate via sudo systemctl status omxlooper.service or log files"
            else
                echo "Enabled omxlooper service"
        fi
    else
        if ! cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service
            then
                echo "Failed to install omxlooper as a service, this is important if you want the video to loop automatically on boot after powerloss"
                echo "Please remedy manually by referencing ./examples/omxlooper.example and installing that file into /etc/systemd/system/omxlooper.service"
        fi
        if ! systemctl start omxlooper.service
            then
                echo "Failed to start omxlooper service!"
                echo "Please investigate via sudo systemctl status omxlooper.service or log files"
            else
                echo "Started omxlooper service!"
        fi
        if ! systemctl enable omxlooper.service
            then
                echo "Failed to enable omxlooper service!"
                echo "Please investigate via sudo systemctl status omxlooper.service or log files"
            else
                echo "Enabled omxlooper service"
        fi
fi

# End of installation
echo "Installation of Video Looper has completed successfully!"
exit 0