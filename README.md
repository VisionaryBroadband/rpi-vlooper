# rpi-vlooper
This repo was created to satisfy a particular need. That need was to loop a video and show media on a screen (or many) continually. It also needed to be easy for the layman to use and update the media themselves as they see fit. In my usecase the users would use PowerPoint to create a slideshow with pictures on timers and possibly add videos into it as well. Then they would export the file as an MP4. After that the user uses WinSCP to upload the file to the videos folder and using last modified timestamps we automatically load the latest video file.

This is where this repo comes into play. This will install all the necessary files and cronjobs to check for new media in that videos folder. The cronjob will check every minute to see if there are new files in that videos folder and if so, kick of a sequence of events that restarts services and logs the old and new videos being swapped out.

## System Requirements
* Raspberry Pi
* Raspberry OS (aka Raspbian) 10 (Buster)
* 4GB+ microSD card
* Display to connect to the raspberry pi (via direct HDMI preferred for audio to work)
* The following software packages will be installed via the install script:
  * (required) `omxplayer`
  * (required) `cec-utils`

## Installation instructions via Git CLI ([installation instructions here](https://github.com/cli/cli/blob/trunk/docs/install_linux.md))
1. `cd ~`
2. `gh repo clone VisionaryBroadband/rpi-vlooper`
3. `cd ~/rpi-vlooper && chmod +x installer.sh`
4. `./installer.sh`

## Other notes
* Users will need to manually setup your method of uploading videos to your rasberry pi.
  * Such as, you might sftp or scp the files onto the pi via Filezilla, WinSCP, or CLI.
  * You could also plug in removable media and manually the copy the files onto the rasberry pi.
  > The files will need to be put into the `~/vlooper/videos` folder
* I would recommend that you have properly configured your localization on your Raspberry Pi with `sudo raspi-config` before installing this repo
  * Set your local timezone
  * Set your keyboard layout (Ie. Generic 104-Key for US or Generic 105-Key-Intl for Great Britain)
  * Set your locale to your regions language pack (Ie. en_US or en_GB)
  * After making these changes, please reboot your Raspberry Pi to ensure all your services have up-to-date information, such as Crontab using the right timezone.
* SMB/NFS support was removed due to compatibility issues and security reasons.
* Forced OS version to be 10 (Buster) as OMX is depreciated in later releases and we want to be as current as possible.

Thank you for using this repository, if you like it feel free to fork it and adapt it to your own needs!
