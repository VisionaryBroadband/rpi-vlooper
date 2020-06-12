# rpi-vlooper
This repo was created to satisfy a particular need. That need was to loop a video and show media on a screen (or many) continually. It also needed to be easy for the layman to use and update the media themselves as they see fit. In my usecase the users would use PowerPoint to create a slideshow with pictures on timers and possibly add videos into it as well. Then they would export the file as an MP4. After that the user uploads the MP4 to a designated SMB Share on our file server. Then I mounted that SMB share in my /etc/fstab file so I could access it from my raspberry PI.

This is where this repo comes into play. This will install all the necessary files and cronjobs to check for new media in that SMB Share. The cronjob will check every minute to see if there are new files in that SMB share and if so, kick of a sequence of events that pulls that file over to the local storage and then pushes the current video back to the SMB share into an "archive" folder and timestamps that file. This way we do not burn up limited disk space on the rpi, and still maintain a backup of the previous files where the users have quick and easy access.

## System Requirements
* Raspberry Pi
* Raspberry OS (aka Raspbian)
* 4GB+ microSD card
* Display to connect to the raspberry pi (via direct HDMI preferred for audio to work)
* The following software packages will be installed via the install script:
  * (required) `omxplayer`
  * (optional) `cifs-utils`
  * (optional) `nfs-common`

## Installation instructions
1. `sudo apt install git -y`
2. `cd ~`
3. `git clone git://github.com/captainfodder/rpi-vlooper.git`
4. `cd ~/rpi-vlooper && chmod +x installer.sh`
5. `./installer.sh`

## Other notes
* If you are not using SMB or NFS to get new videos automatically, then you will need to manually setup your method of uploading videos to your rasberry pi.
  * Such as, you might sftp or scp the files onto the pi via Filezilla or CLI.
  * You could also plug in removable media and manually the copy the files onto the rasberry pi.
  > The files will need to be put into the `/mnt/tvMedia` folder, and named whatever you chose for the `$newVideo` file name (see /inc/main.cfg)

Thank you for using this repository, if you like it feel free to fork it and adapt it to your own needs!
