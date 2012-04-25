This software package was originally posted 12/29/2011 BY trboars@yahoo.com @ http://groups.yahoo.com/group/MOTOTRBO/message/2490
The mediafire links has been vaporized. Reposted here unmodified for all.

Original posting from groups.yahoo.com/groups/mototrbo


Here is new version ARS service and APRS gateway for TRBO. Old version had not
one file which was needed to run.

http://www.mediafire.com/file/rm2wv65dfhznh49/TRBO-NET-1.2.tar.gz

Extract with "tar xvfz TRBO-NET-1.2.tar.gz", cd TRBO-NET-1.2 and read README
file.

This was written with wireshark and other network monitoring, so all may not
work.

---------------------

We are Anonymous. We now write ham software. :)


This packet contain Perl modules to talk UDP to motorola's turbo radios.
It consist of several modules: ARS for automatic registration service, TMS
for text message receive and sending, LOC for location packet
request and parsing, and NET for glueing those together.

There is also application, 'arsed', ARS-E daemon (E stands for
Extendable), which use mentioned modules to provide registration
service and location + text message gateway to APRS-IS.

This ist going to be very buggy and unreliable, since its has been
put together by loking at UDP packets sent and received by radio
using wireshark (mad reverse engineering skillz). Unfortunately there
isn't no docs available to protocol.

It has been tested on Linux (ubuntu, debian) only, but it can
work on Windows after installing perl there.


To install:

0) get some dependencies (these are for debian/ubuntu):
sudo apt-get install libyaml-tiny-perl
sudo apt-get install libdate-calc-perl
sudo apt-get install libjson-perl


1) first, install Ham::APRS::FAP perl module
for parse APRS-IS and connections:

wget http://search.cpan.org/CPAN/authors/id/H/HE/HESSU/Ham-APRS-FAP-1.18.tar.gz
tar xvfz Ham-APRS-FAP-1.18.tar.gz
cd Ham-APRS-FAP-1.18
perl Makefile.PL
make
sudo make install


2) install TRBO::NET and ARS-E:

tar xvfz TRBO-NET-1.0.tar.gz
perl Makefile.PL
cd TRBO-NET-1.0
make
make test
sudo make install

That install perl mods in /usr/local/..perl libs,
and 'arsed' program in /usr/local/bin.

3) configure teh ARS-E daemon:

sudo cp tools/arsed.conf.example /etc/arsed.conf

edit /etc/arsed.conf to match your needs

run arsed (as normal user, no need to run as root)

It will print lot of debug log on console, redirect it to file to
get log file. ("arsed 2>&1 | tee arsed.log") Sorry no log file support
built in yet. Next version!


4) connect radio to computer:

- connect turbo radio to Linux box using USB

- config IP address on usb0 interface which should appear,
maybe run 'dhclient usb0' to get address

- make sure your IP default gateway still points to teh internets, not
to radio (dhclient by default points it at radio), so that
APRS-IS can be found too

- make sure you can ping radio (with radio IP address configured in
CPS)

- make sure you have IP route covering all radios pointing to the
gateway radio... if your CAI network is 10, do a
"route add -net 10.0.0.0/8 gw radios-ip-address"

- turbo HT with display seems to work on Linux as it is, the
one without display does not automaticly brink up usb0 interface? Some
kernel hack needed?


5) use it:

- send text message to gateway radio's ID: it has 'who' command to
list registered radios ('w' for short).

- send 'aprs <callsign> <message>' to send text message to APRS-IS

- once radio starts sending positions, they will be sent to the
APRS-IS too


6) there's web page for network status display in web/, in PHP. U can run
it on same computer with arsed, or on another, but then you'll need to
expose json state file using HTTP to status display.


To see packet sent to and from radios, run
"sudo tcpdump -i usb0 -n -s0". When another radio turn on with ARS
on, should see packet coming from radio to ARS server, if
radios configured right. Wireshark application can be used to see more.


Notes on radio config
---------------------

CAI network numbers must match on all radios and arsed config!

The local IP address configured for radio is only the
address used used for USB computer link, it's not visible
anywhere else. It must not overlap CAI network. Use CAI
network 10 and PC-USB IP address in 192.168.something and
you'll be happy. CAI 10 so that radio IPs will be 10.x.y.z
and won't overlap Internets addresses, so that you can have the
ARS computer connected to both radio and teh internets.

You can not ping other radios, only your local radio.
The radio only pass UDP packets on configured ports. No TCP, no
ICMP.

The gateway radio must not have ARS/TMS configured. It need
have "pass to PC" checkbox enabled so that packets it gets
are given to arsed.

Other radios need have ARS/TMS configured, pointing to the
ID of gateway radio which is connected to ARS-E PC.

DO NOT enable ARS on DMR-MARC or some other net without their
approval. Will congest. Only use it on your local timeslot.

This code currently only supports one radio, so no GPS offloading to
another channel/timeslot.

It's handy to configure radio with three channels for same timeslot:
- One without ARS (I want to listen in and talk but not announce my
presence to world)
- One with ARS and GPS revert set to current/default (I want to announce
my presence and GPS position)
- One with ARS but GPS revert channel set to None (I want to announce my
presence with ARS, but not my exactp GPS position)