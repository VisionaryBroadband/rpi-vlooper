#!/bin/bash

# Declare Shell color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Declare default variables
newFile="announcements.mp4"
playFile="announcement.mp4"

# Check if this is being installed as root or not
if [ "$EUID" -ne 0 ]
    then
        # Set HISTIGNORE to ignore piped-password-sudo commands to protect the sudo password from being stored in plaintext in logs
        export HISTIGNORE='*sudo -S*'
        read -srp "[  INPUT  ] Please enter sudo password: " sudoPW
fi

# Warn users that this installation script is assumption-heavy
printf "\n"
echo -e "[ ${YELLOW}WARNING${NC} ] This installation script makes a lot of assumptions and you may encounter errors."

# Check for sufficient disk space
diskUsage=$(df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 }' | grep root | awk '{ print $1}' | cut -d '%' -f1)
if [[ $diskUsage -ge 90 ]]
    then
        echo -e "[ ${YELLOW}WARNING${NC} ] Disk 90% or more full!"
        read -rp "[  INPUT  ] Would you like to try the installation anyways [y/N]? " diskWarn
        if [ "$diskWarn" != "y" ]
            then
                echo -e "[  ${RED}ABORT${NC}  ] Cancelling installation..."
                exit 0
        fi
fi

# Check for compatible OS
distroCheck=$(lsb_release -irdc | head -n 1 | awk '{print $3}')
versionCheck=$(lsb_release -irdc | head -n 3 | tail -n 1 | awk '{print $2}')
if [ "$distroCheck" != "Raspbian" ]
    then
        echo -e "[ ${RED}FAILED${NC}  ] OS is incompatible, required OS: Raspbian / RaspberryOS"
        exit 1
    else
        if [[ $versionCheck -lt 10 ]]
            then
                echo -e "[ ${YELLOW}WARNING${NC} ] OS Version is less than 10 (Buster), you may encounter incompatibilities"
                read -rp "[  INPUT  ] Would you like to proceed anyways [y/N]? " osVersion
                if [ "$osVersion" != "y" ]
                    then
                        echo -e "[  ${RED}ABORT${NC}  ] Cancelling installation..."
                        exit 1
                    else
                        echo -e "[   ${GREEN}OK${NC}    ] Proceeding with installation..."
                fi
        fi
fi

# Setup passwordless sudo for killall & tee so that vlooper can start/stop vlooper w/o needing a sudo password everytime
## First check if this is being installed as root or not
if [ "$EUID" -ne 0 ]
    then
        echo "[   ---   ] Setting up sudo exemption for vlooper script to stop services"
        touch ./examples/vlooper-exception
        echo "$USER ALL=(ALL) NOPASSWD: /bin/systemctl,/usr/bin/tee" > ./examples/vlooper-exception
        echo "$sudoPW" | sudo -S -k chown root:root ./examples/vlooper-exception
        echo "$sudoPW" | sudo -S -k mv ./examples/vlooper-exception /etc/sudoers.d/
fi

# Prompt user how they want to import their new videos to the vlooper service
read -rp "[  INPUT  ] Would you like to retrieve your new videos from a remote file share such as SMB or NFS [y/N]? " mediaMethod
if [[ "$mediaMethod" = "y" ]]
    then
        read -rp "[  INPUT  ] Would you like to use SMB or NFS [smb/nfs]? " remoteMethod
    else
        echo "[  INPUT  ] In order to play new videos automatically, you will need to upload them into this folder: /mnt/tvMedia"
fi

# Check for dependencies and ask to install them if unmet
echo "[   ---   ] Checking dependencies..."
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
            read -rp "[  INPUT  ] $package not installed, install [y/N]? " doInstall
            if [[ "$doInstall" = "y" ]]
                then
                    echo "[   ---   ] Installing $package..."
                    if [ "$EUID" -ne 0 ]
                        then
                            if ! echo "$sudoPW" | sudo -S -k apt install "$package" -y > /dev/null 2>&1
                                then
                                    echo -e "[ ${RED}FAILED${NC}  ] Could not install $package! Aborting installation..."
                                    exit 1
                                else
                                    echo -e "[   ${GREEN}OK${NC}    ] Installed $package!"
                            fi
                        else
                            if ! apt install "$package" -y > /dev/null 2>&1
                                then
                                    echo -e "[ ${RED}FAILED${NC}  ] Could not install $package! Aborting installation..."
                                    exit 1
                                else
                                    echo -e "[   ${GREEN}OK${NC}    ] Installed $package!"
                            fi
                    fi
                else
                    echo -e "[  ${RED}ABORT${NC}  ] Not installing $package, aborting installation"
                    exit 1
            fi
    fi
done
echo -e "[   ${GREEN}OK${NC}    ] Dependencies met! Installing Video Looper now..."

# Update the main.cfg file for usage
echo "[   ---   ] Building configuration file..."
read -rp "[  INPUT  ] What file name will your new videos be titled [$newFile]? " newFileInput
if [[ -n $newFileInput ]]
    then
        newFile="$newFileInput"
fi
read -rp "[  INPUT  ] What file name will your playing video be titled [$playFile]? " playFileInput
if [[ -n $playFileInput ]]
    then
        playFile="$playFileInput"
fi
if ! sed -i'' -e "s,# fileOwner=,fileOwner=$USER,ig" -e "s,# baseDir=,baseDir=$HOME/vlooper,ig" -e "s,newVideo=\"announcements.mp4\",newVideo=\"$newFile\",ig" -e "s,curVideo=\"announcement.mp4\",curVideo=\"$playFile\",g" ./examples/main.example
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not build configuration file, aborting installation!"
        exit 1
fi

# Update the vlogroate conf file for usage
if ! sed -i'' -e "s,create 660,create 660 $USER $USER,g" ./examples/vlogrotate.example
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not build vlogroate configuration file, aborting installation!"
        exit 1
fi

# Update both scripts to specify the full filepath to the main.cfg
if ! sed -i'' -e "s,#source,source $HOME/vlooper/inc/main.cfg,g" ./examples/vlooper.example
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not update vlooper script with main.cfg path"
        exit 1
fi
if ! sed -i'' -e "s,#source,source $HOME/vlooper/inc/main.cfg,g" ./examples/vupdate.example
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not update vupdate script with main.cfg path"
        exit 1
fi

# Create all the directories for the script to be installed in
echo "[   ---   ] Creating directories..."
if ! mkdir -p ~/vlooper/inc
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not create directories"
        exit 1
fi
if ! mkdir -p ~/vlooper/video
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not create directories"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k mkdir -p /mnt/tvMedia 2>&1
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /mnt/tvMedia for remoteFS mount, aborting installation!"
                exit 1
        fi
    else
        if ! mkdir -p /mnt/tvMedia 2>&1
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /mnt/tvMedia for remoteFS mount, aborting installation!"
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
                read -rp "[  INPUT  ] What is the filepath for the SMB share you wish to mount (Ex. //192.168.0.1/TvMedia)? " smbShare
                read -rp "[  INPUT  ] What username should be used to connect to the SMB Share (leave blank for none)? " smbUser
                if [[ -n "$smbUser" ]]
                    then
                        read -rp "[  INPUT  ] What password should be used to connect to the SMB Share? " smbPass
                        read -rp "[  INPUT  ] What domain should be used to connect to the SMB Share (leave blank for none)? " smbDomain
                        # Create the SMB credential file
                        if ! touch ~/.smbCreds 2>&1
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not create SMB credential file, aborting installation!"
                                exit 1
                        fi
                        # Setup SMB credential file permissions
                        if ! chmod 600 ~/.smbCreds 2>&1
                            then
                                echo -e "[ ${YELLOW}WARNING${NC} ] Could not secure SMB credential file, please secure manually with: chmod 600 ~/.smbCreds"
                        fi
                        # Setup the SMB credential file
                        if ! echo "user=$smbUser" >> ~/.smbCreds
                            then
                                echo -e "[ ${YELLOW}WARNING${NC} ] Could not set SMB User, please manually set 'user=$smbUser' with: nano ~/.smbCreds"
                        fi
                        if ! echo "password=$smbPass" >> ~/.smbCreds
                            then
                                echo -e "[ ${YELLOW}WARNING${NC} ] Could not set SMB Password, please manually set 'password=$smbPass' with: nano ~/.smbCreds"
                        fi
                        if [[ -n "$smbDomain" ]]
                            then
                                if ! echo "domain=$smbDomain" >> ~/.smbCreds
                                    then
                                        echo -e "[ ${YELLOW}WARNING${NC} ] Could not set SMB Domain, please manually set 'domain=$smbDomain' with: nano ~/.smbCreds"
                                fi
                        fi
                fi
                # Setup the SMB connection
                if [[ -n "$smbUser" ]]
                    then
                        if ! echo "$sudoPW" | sudo -S -k echo "$smbShare    /mnt/tvMedia  cifs    uid=$USER,gid=$USER,credentials=$HOME/.smbCreds,iocharset=utf8,rw 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not add SMB Mount to /etc/fstab"
                                exit 1
                        fi
                    else
                        if ! echo "$sudoPW" | sudo -S -k echo "$smbShare    /mnt/tvMedia  cifs    uid=$USER,gid=$USER,iocharset=utf8,rw 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not add SMB Mount to /etc/fstab"
                                exit 1
                        fi
                fi
            else
                # Setup the NFS connection
                read -rp "[  INPUT  ] What is the filepath for the NFS share you wish to mount (Ex. 192.168.0.1:/TvMedia)? " nfsShare
                read -rp "[  INPUT  ] What username should be used to connect to the NFS Share (leave blank for none)? " nfsUser
                if [[ -n "$nfsUser" ]]
                    then
                        read -rp "[  INPUT  ]What password should be used to connect to the NFS Share? " nfsPass
                        if ! echo "$sudoPW" | sudo -S -k echo "$nfsShare    /mnt/tvMedia  nfs    username=$nfsUser,password=$nfsPass,rw,noexec,nosuid 0 0" | sudo tee -a /etc/fstab > /dev/null /2>&1
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not add NFS Mount to /etc/fstab"
                                exit 1
                        fi
                    else
                        if ! echo "$sudoPW" | sudo -S -k echo "$nfsShare    /mnt/tvMedia  nfs    rw,noexec,nosuid 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not add NFS Mount to /etc/fstab"
                                exit 1
                        fi
                fi
        fi
        # Mount the remote file share
        if ! echo "$sudoPW" | sudo -S -k mount -a
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not mount the remote file share, please check /etc/fstab for errors!"
                exit 1
        fi
    else
        # Update main.cfg to comment network var, and set it to true to pass future checks.
        if ! sed -i'' -e "s,#smbResult=\"true\",smbResult=\"true\",ig" -e "s,smbResult=\$(,#smbResult=\$(,g" ./examples/main.example
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not update main.cfg with network parameters, aborting installation!"
                exit 1
        fi
fi

# Install the files into those directories
echo "[   ---   ] Installing files into directories..."
if ! cp ./examples/vupdate.example ~/vlooper/vupdate.sh
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not install vupdate script"
        exit 1
    else
        if ! chmod +x ~/vlooper/vupdate.sh
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not make vupdate script executable"
                exit 1
        fi
fi
if ! cp ./examples/main.example ~/vlooper/inc/main.cfg
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not install configuration file and make executable"
        exit 1
    else
        if ! chmod +x ~/vlooper/inc/main.cfg
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not make main.cfg script executable"
                exit 1
        fi
fi
if ! cp ./examples/announcement.mp4 "$HOME/vlooper/video/$playFile"
    then
        echo -e "[ ${RED}FAILED${NC}  ] Could not install demo video file"
        exit 1
fi
if [ "$EUID" -ne 0 ]
    then
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/vlooper.example /usr/local/bin/vlooper.sh
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install vlooper script!"
                exit 1
            else
                if ! echo "$sudoPW" | sudo -S -k chmod +x /usr/local/bin/vlooper.sh
                    then
                        echo -e "[ ${RED}FAILED${NC}  ] Could not make vlooper script executable"
                        exit 1
                fi
        fi
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k touch /var/log/vlooper.log
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /var/log/vlooper.log"
                exit 1
            else
                if ! echo "$sudoPW" | sudo -S -k chown "$USER":root /var/log/vlooper.log
                    then
                        echo -e "[ ${RED}FAILED${NC}  ] Could not update ownerships of /var/log/vlooper.log"
                        exit 1
                    else
                        if ! echo "$sudoPW" | sudo -S -k chmod 660 /var/log/vlooper.log
                            then
                                echo -e "[ ${RED}FAILED${NC}  ] Could not set permissions of /var/log/vlooper.log"
                                exit 1
                        fi
                fi
        fi
    else
        if ! cp ./examples/vlooper.example /usr/local/sbin/vlooper.sh
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install vlooper script"
                exit 1
            else
                if ! echo "$sudoPW" | sudo -S -k chmod +x /usr/local/sbin/vlooper.sh
                    then
                        echo -e "[ ${RED}FAILED${NC}  ] Could not make vlooper script executable"
                        exit 1
                fi
        fi
        if ! cp ./examples/vlogrotate.example /etc/logrotate.d/vlooper
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /etc/logrotate.d/vlooper"
                exit 1
        fi
        if ! touch /var/log/vlooper.log
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not create /var/log/vlooper.log"
                exit 1
        fi
fi

# Make symlink to vupdate script
if [ "$EUID" -ne 0 ]
    then
        echo "[   ---   ] Creating symbolic link to vupdate script..."
        echo -e "[  ${CYAN}INFO${NC}   ] You can invoke this script to force a video update simply by typing: vupdate"
        if ! echo "$sudoPW" | sudo -S -k ln -s "$HOME/vlooper/vupdate.sh" /usr/local/bin/vupdate
            then
                echo -e "[ ${YELLOW}WARNING${NC} ] --- Could not create vupdate symlink, you can optionally create this if you choose so"
        fi
    else
        echo "[   ---   ] Creating symbolic link to vupdate script..."
        if ! ln -s ~/vlooper/vupdate.sh /usr/local/sbin/vupdate
            then
                echo -e "[ ${YELLOW}WARNING${NC} ] --- Failed to create vupdate symlink, you can optionally create this if you choose so"
        fi
fi

# Setup crontab
echo "[   ---   ] Setting up crontab to run vupdate every minute"
if [ "$EUID" -ne 0 ]
    then
        if ! crontab -l | { cat; echo "* * * * * /usr/local/bin/vupdate"; } | crontab -
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install cronjob to check for new media every minute"
                exit 1
        fi
    else
        if ! crontab -l | { cat; echo "* * * * * /usr/local/sbin/vupdate"; } | crontab -
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install cronjob to check for new media every minute"
                exit 1
        fi
fi

# Check if script is being ran over SSH
if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]
    then
        SESSION_TYPE=remote/ssh
    else
        case $(ps -o comm= -p $PPID) in
            sshd|*/sshd) SESSION_TYPE=remote/ssh
        ;;
        esac
fi

# Setup vlooper service so the video loop starts on boot and stays alive
echo "[   ---   ] Installing Video Looper service..."
if [ "$EUID" -ne 0 ]
    then
        if ! sed -i'' -e "s,ExecStart=,ExecStart=/usr/local/bin/vlooper.sh,ig" -e "s,User=,User=$USER,g" ./examples/vlooper_svc.example
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not build vlooper service file, aborting installation!"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k cp ./examples/vlooper_svc.example /etc/systemd/system/vlooper.service
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install vlooper as a service, this is important if you want the video to loop automatically on boot after powerloss"
                echo -e "[  ${CYAN}INFO${NC}   ] Please remedy manually by referencing ./examples/vlooper_svc.example and installing that file into /etc/systemd/system/vlooper.service"
                exit 1
        fi
        if ! echo "$sudoPW" | sudo -S -k systemctl daemon-reload
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not reload systemctl daemon!"
                exit 1
        fi
        if [[ -n $SESSION_TYPE ]]
            then
                if ! echo "$sudoPW" | sudo -S -k systemctl start vlooper.service
                    then
                        echo -e "[ ${RED}FAILED${NC}  ] Could not start vlooper service!"
                        echo -e "[  ${CYAN}INFO${NC}   ] Please investigate via sudo systemctl status vlooper.service or log files"
                        exit 1
                    else
                        echo -e "[   ${GREEN}OK${NC}    ] Started vlooper service!"
                fi
            else
                echo -e "[  ${CYAN}INFO${NC}   ] It looks like you are running this script locally instead of over SSH"
                echo -e "[  ${CYAN}INFO${NC}   ] When the Video Looper service starts, the video playback will use this current display"
                echo -e "[  ${CYAN}INFO${NC}   ] This means you will not be able to see the console anymore."
                echo -e "[  ${CYAN}INFO${NC}   ] Even though the video will be playing over your console, you can still type commands so long as you're logged in"
                echo -e "[  ${CYAN}INFO${NC}   ] You can stop the service and regain visibility of your console with: sudo systemctl stop vlooper"
                read -rp "[  INPUT  ] Do you want to start the Video Looper service now [y/N]? " startService
        fi
        if [[ "$startService" = "y" ]]
            then
                if ! echo "$sudoPW" | sudo -S -k systemctl start vlooper.service
                    then
                        echo -e "[ ${RED}FAILED${NC}  ] Could not start vlooper service!"
                        echo -e "[  ${CYAN}INFO${NC}   ] Please investigate via sudo systemctl status vlooper.service or log files"
                        exit 1
                    else
                        echo -e "[   ${GREEN}OK${NC}    ] Started vlooper service!"
                fi
            else
                if [[ -n $startService ]]
                    then
                        echo -e "[  ${CYAN}INFO${NC}   ] You can start the Video Looper service whenever you are ready with: sudo systemctl start vlooper"
                fi
        fi
        if ! echo "$sudoPW" | sudo -S -k systemctl enable vlooper.service > /dev/null 2>&1
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not enable vlooper service!"
                echo -e "[  ${CYAN}INFO${NC}   ] Please investigate via sudo systemctl status vlooper.service or log files"
                exit 1
            else
                echo -e "[   ${GREEN}OK${NC}    ] Enabled vlooper service"
        fi
    else
        if ! sed -i'' -e "s,ExecStart=,ExecStart=/usr/local/sbin/vlooper.sh,ig" -e "s,User=,User=$USER,g" ./examples/vlooper_svc.example
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not build vLooper service file, aborting installation!"
                exit 1
        fi
        if ! cp ./examples/vlooper_svc.example /etc/systemd/system/vlooper.service
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not install vlooper as a service, this is important if you want the video to loop automatically on boot after powerloss"
                echo -e "[  ${CYAN}INFO${NC}   ] Please remedy manually by referencing ./examples/vlooper_svc.example and installing that file into /etc/systemd/system/vlooper.service"
                exit 1
        fi
        if ! systemctl start vlooper.service
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not start vlooper service!"
                echo -e "[  ${CYAN}INFO${NC}   ] Please investigate via sudo systemctl status vlooper.service or log files"
                exit 1
            else
                echo -e "[   ${GREEN}OK${NC}    ] Started vlooper service!"
        fi
        if ! systemctl enable vlooper.service > /dev/null 2>&1
            then
                echo -e "[ ${RED}FAILED${NC}  ] Could not enable vlooper service!"
                echo -e "[  ${CYAN}INFO${NC}   ] Please investigate via sudo systemctl status vlooper.service or log files"
                exit 1
            else
                echo -e "[   ${GREEN}OK${NC}    ] Enabled vlooper service"
        fi
fi

# End of installation
echo -e "[   ${GREEN}OK${NC}    ] Installation of Video Looper has completed successfully!"
exit 0