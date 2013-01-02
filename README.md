ARS-E DAEMON AUTOMATIC REGISTRATION SERVICE EXTENDABLE  
Demo Video: http://youtu.be/85EdiW7mbXQ  

Install Instructions  
Assumes a Clean install of Debian Squeeze  


Update system and install prereqs
```
sudo apt-get update  
sudo apt-get install openssh-server git libyaml-tiny-perl libdate-calc-perl libjson-perl  libtest-pod-coverage-perl  
```

Download and install the Ham APRS module
```
mkdir ~/src  
cd ~/src  
wget http://search.cpan.org/CPAN/authors/id/H/HE/HESSU/Ham-APRS-FAP-1.18.tar.gz  
tar -zxvf ./Ham-APRS-FAP-1.18.tar.gz  
cd Ham-APRS-FAP-1.18  
perl Makefile.PL  
make  
sudo make install 
cd ..  
```
Install the TRBO-NET arsed program  

```
git clone https://github.com/KD8EYF/TRBO-NET.git  
cd TRBO-NET/  
perl Makefile.PL  
make  
sudo make install  
```

Edit the config file by hand to include the DMR radio users you want to listen for.  
the mi5 network config is include as an example of what we did in michigan:  

```
cp configs/arsed.mi5.conf /etc/arsed.conf  
vi configs/arsed.mi5.conf  
```

Reccommend static networking config in /etc/network/interfaces  
Assuming Radio IP of 192.168.10.1 and PC ip of 192.168.10.2

    iface usb0 inet static
        address 192.168.10.2
        netmask 255.255.255.0
        up route add -net 12.0.0.0/8 gw 192.168.10.1
        down route del -net 12.0.0.0/8 gw 192.168.10.1

RUN THE PROGRAM

```
arsed 
```

Install Apache webserver  
```
apt-get install apache2 libapache2-mod-php5  
cp ~/src/TRBO-NET/web/* /var/www/  
```

connect turbo radio to Linux box using USB  
Device should enumerate and automatically create a network interface. If not check kernel support  

- send text message to gateway radio's ID: it has 'who' command to list registered radios ('w' for short).  
- send 'aprs <callsign> <message>' to send text message to APRS-IS  

once radio starts sending positions, they will be sent to the APRS-IS too  !

View the WebStatus  
- http:/[IP ADDRESS OF SERVER]/state.php  

