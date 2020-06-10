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

# Check for dependencies and ask to install them if unmet
pkgInstalled=$(dpkg --get-selections | grep "omxplayer" | awk '{print $1}')
if [[ -z $pkgInstalled ]]
    then
        read -rp "omxplayer not installed, install [y/N]?" installOMX
        if [ "$installOMX" = "y" ]
            then
                echo "Installing omxplayer..."
                if [ "$EUID" -ne 0 ]
                    then
                        if ! echo "$sudoPW" | sudo -S -k apt install omxplayer -y > /dev/null 2>&1
                            then
                                echo "Failed to install omxplayer! Aborting installation..."
                                exit 1
                            else
                                echo "Installed omxplayer!"
                        fi
                    else
                        if ! apt install omxplayer -y > /dev/null 2>&1
                            then
                                echo "Failed to install omxplayer! Aborting installation..."
                                exit 1
                            else
                                echo "Installed omxplayer!"
                        fi
                fi
            else
                echo "Not installing omxplayer, aborting installation"
                exit 1
        fi
    else
        echo "Dependencies met! Installing Video Looper now..."
fi

# Update the main.cfg file for usage
echo "Building configuration file..."
if ! sed -e "s,# fileOwner=,fileOwner=$USER,ig" -e "s,# baseDir=,baseDir=$HOME/vlooper,g" ./examples/main.example > ./examples/main.temp
    then
        echo "Failed to build configuration file, aborting installation!"
        exit 1
fi
if ! mv ./examples/main.temp ./examples/main.example > /dev/null 2>&1
    then
        echo "Failed to build configuration file, aborting installation!"
        exit 1
fi

# Create all the directories for the script to be installed in
echo "Creating directories..."
if ! mkdir ~/vlooper > /dev/null 2>&1
    then
        echo "Failed to create ~/vlooper"
        exit 1
fi
if ! mkdir ~/vlooper/video > /dev/null 2>&1
    then
        echo "Failed to create ~/vlooper/video"
        exit 1
fi
if ! mkdir ~/vlooper/inc > /dev/null 2>&1
    then
        echo "Failed to create ~/vlooper/inc"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k mkdir /mnt/tvMedia > /dev/null 2>&1
            then
                echo "Failed to create /mnt/tvMedia"
                exit 1
        fi
    else
        if ! mkdir /mnt/tvMedia > /dev/null 2>&1
            then
                echo "Failed to create /mnt/tvMedia"
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
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper > /dev/null 2>&1
            then
                echo "Failed to create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k touch /var/log/vlooper.log > /dev/null 2>&1
            then
                echo "Failed to create /var/log/vlooper.log"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service > /dev/null 2>&1
            then
                echo "Failed to install omxlooper service"
                exit 1
        fi
    else
        if ! cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper > /dev/null 2>&1
            then
                echo "Failed to create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! touch /var/log/vlooper.log > /dev/null 2>&1
            then
                echo "Failed to create /var/log/vlooper.log"
                exit 1
        fi
        if ! cp ./examples/omxlooper.example /etc/systemd/system/omxlooper.service > /dev/null 2>&1
            then
                echo "Failed to install omxlooper service"
                exit 1
        fi
fi

# Make symlink to vupdate script
echo "Creating symbolic link to vupdate script... You can invoke this script simply be typing: vupdate"
if ! ln -s ~/vlooper/vupdate.sh /usr/bin/vupdate > /dev/null 2>&1
    then
        echo "Failed to create vupdate symlink, you can optionally create this if you choose so"
    fi
echo "Creating symbolic link to vlooper script... You can invoke this script simply be typing: vlooper {start|stop|restart}"
if ! ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper > /dev/null 2>&1
    then
        echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
        echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
fi
echo "Creating symbolic link to vloop_boot script..."
if ! ln -s ~/vlooper/vlooper_boot.sh /usr/bin/vlooper_boot > /dev/null 2>&1
    then
        echo "Failed to create vlooper symlink, this is necessary in order for the omxlooper service to run on boot!"
        echo "  - Please manually create this with: ln -s ~/vlooper/vlooper.sh /usr/bin/vlooper"
fi

# Setup crontab
echo "Setting up crontab to run vupdate every minute"
if ! crontab -l | { cat; echo "* * * * * /root/vlooper/vupdate.sh"; } | crontab -
    then
        echo "Failed to install cronjob to check for new media every minute"
        exit 1
fi

# Setup passwordless sudo for killall so that vlooper can start/stop omxplayer w/o needing a sudo password everytime
## First check if this is being installed as root or not
if [ "$EUID" -ne 0 ]
    then
        echo "Setting up sudo exemption for vlooper script to stop services"
        touch ./examples/vlooper-exception > /dev/null 2>&1
        echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/killall" > ./examples/vlooper-exception > /dev/null 2>&1
        echo "$sudoPW" | sudo -S -k chown root:root ./examples/vlooper-exception > /dev/null 2>&1
        echo "$sudoPW" | sudo -S -k mv ./examples/vlooper-exception /etc/sudoers.d/ > /dev/null 2>&1
fi

# Setup omxLooper service so the video loop starts on boot and stays alive
echo "Installing omxLooper service..."
if ! sed -e "s,WorkingDirectory=,WorkingDirectory=$HOME/vlooper,ig" ./examples/omxlooper.example > ./examples/omxlooper.temp
    then
        echo "Failed to build omxLooper service file, aborting installation!"
        exit 1
fi
if ! mv ./examples/omxlooper.temp ./examples/omxlooper.example > /dev/null 2>&1
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