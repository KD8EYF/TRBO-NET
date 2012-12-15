ARS-E DAEMON
AUTOMATIC REGISTRATION SERVICE EXTENDABLE
DEMO VIDEO HERE
http://youtu.be/85EdiW7mbXQ

___________________________________
DEBIAN SQUEEZE INSTALL INSTRUCTIONS  

sudo apt-get update  
sudo apt-get install openssh-server git libyaml-tiny-perl libdate-calc-perl libjson-perl  libtest-pod-coverage-perl  
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


