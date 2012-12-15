ARS-E DAEMON  
AUTOMATIC REGISTRATION SERVICE EXTENDABLE  
Demo Video: http://youtu.be/85EdiW7mbXQ  

DEBIAN SQUEEZE INSTALL INSTRUCTIONS  

Update system and install prereqs
- sudo apt-get update  
- sudo apt-get install openssh-server git libyaml-tiny-perl libdate-calc-perl libjson-perl  libtest-pod-coverage-perl  

mkdir ~/src  
cd ~/src  
wget http://search.cpan.org/CPAN/authors/id/H/HE/HESSU/Ham-APRS-FAP-1.18.tar.gz  
tar -zxvf ./Ham-APRS-FAP-1.18.tar.gz  
cd Ham-APRS-FAP-1.18  
perl Makefile.PL  
make  
sudo make install  
cd..

git clone https://github.com/KD8EYF/TRBO-NET.git  
cd TRBO-NET/  
perl Makefile.PL  
make test  
make  
sudo make install  

Edit the config file by hand to include the DMR radio users you want to listen for.  
the mi5 network config is include as an example of what we did in michigan:  

vi configs/arsed.mi5.conf  
cp configs/arsed.mi5.conf /etc/arsed.conf  

Run the Program:  
arsed 

Optional: Install Apache webserver  
apt-get install apache2 libapache2-mod-php5  
cp ~/src/TRBO-NET/web/* /var/www/  

- connect turbo radio to Linux box using USB  
- config IP address on usb0 interface which should appear, maybe run 'dhclient usb0' to get address  
- make sure your IP default gateway still points to teh internets, not to radio (dhclient by default points it at radio), so that APRS-IS can be found too  
- make sure you can ping radio (with radio IP address configured in CPS)  
- make sure you have IP route covering all radios pointing to the gateway radio... if your CAI network is 10, do a "route add -net 10.0.0.0/8 gw radios-ip-address"  
- turbo HT with display seems to work on Linux as it is, the one without display does not automaticly brink up usb0 interface? Some kernel hack needed?  
- send text message to gateway radio's ID: it has 'who' command to list registered radios ('w' for short).  
- send 'aprs <callsign> <message>' to send text message to APRS-IS  
- once radio starts sending positions, they will be sent to the APRS-IS too  

View the WebStatus  
http:/[IP ADDRESS OF SERVER]/state.php  

