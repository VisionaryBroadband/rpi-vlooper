# rpi-vlooper
This repo was created to satisfy a particular need. That need was to loop a video and show media on a screen (or many) continually. It also needed to be easy for the layman to use and update the media themselves as they see fit. In my usecase the users would use PowerPoint to create a slideshow with pictures on timers and possibly add videos into it as well. Then they would export the file as an MP4. After that the user uploads the MP4 to a designated SMB Share on our file server. Then I mounted that SMB share in my /etc/fstab file so I could access it from my raspberry PI.

This is where this repo comes into play. This will install all the necessary files and cronjobs to check for new media in that SMB Share. The cronjob will check every minute to see if there are new files in that SMB share and if so, kick of a sequence of events that pulls that file over to the local storage and then pushes the current video back to the SMB share into an "archive" folder and timestamps that file. This way we do not burn up limited disk space on the rpi, and still maintain a backup of the previous files where the users have quick and easy access.

## System Requirements
* Raspberry Pi
* Reasberry OS (aka Raspbian)
* 4GB+ microSD card
* Display to connect to the raspberry pi (via direct HDMI preferred for audio to work)

## Installation instructions
1. `cd ~`
2. `git clone https://github.com/captainfodder/rpi-vlooper.git`
3. `cd ~/rpi-vlooper`
4. `chmod +x installer.sh`
5. `./installer.sh`

Thank you for using this repository, if you like it feel free to fork it and adapt it to your own needs!
