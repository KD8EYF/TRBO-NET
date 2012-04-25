
use Test;
BEGIN { plan tests => 1 + 2 + 5 + 5 };
use TRBO::LOC;
use Data::Dumper;
ok(1);

my $loc = new TRBO::LOC(
	'debug' => 0,
	'sock' => undef,
	'cai_net' => 1,
	'port' => 4007,
);

# command from sw to radio: start sending every 30 seconds (1e)
# 2nd byte is length of following data
# 09 0a 22 04 37 27 17 07 50 34 31 1e
#
# initial loc from radio (no fix)
# 0b 07 22 04 37 27 17 07 38

#          cmd len static hdr?  st ??
my $msg = '0d  08  220437271707 37 0f';
$msg =~ s/\s+//g;
my $bin = pack('H*', $msg);
my %init_h = (
	'src_id' => 1234,
);
my %h = %init_h;
my $retval = $loc->decode(\%h, $bin);

ok($retval, 1, "failed to parse a no-fix loc packet");
ok($h{'class'}, 'loc', "wrong packet class");

#       cmd len static hdr?  st lat      lon      wtf?
$msg = '0d  11  220437271707 51 4f47f0b1 1acc9a95 014e';
$msg =~ s/\s+//g;
$bin = pack('H*', $msg);
%h = %init_h;
$retval = $loc->decode(\%h, $bin);

ok($retval, 1, "failed to parse a fix loc packet");
ok($h{'class'}, 'loc', "wrong packet class");
ok($h{'msg'}, 'loc', "wrong packet msg");
ok(sprintf('%.6f', $h{'latitude'}), "55.744465", "wrong latitude");
ok(sprintf('%.6f', $h{'longitude'}), "37.686422", "wrong longitude");

#       cmd len static hdr?  st lat      lon      wtf?!?
$msg = '0d  16  220437271707 51 4f47f3c1 1acc7c42 24156c006f568d';
$msg = '0d  16  220437271707 51 4f47f3c1 1acc7c42 24156c006f568d';
$msg =~ s/\s+//g;
$bin = pack('H*', $msg);
%h = %init_h;
$retval = $loc->decode(\%h, $bin);

ok($retval, 1, "failed to parse fix loc packet");
ok($h{'class'}, 'loc', "wrong packet class");
ok($h{'msg'}, 'loc', "wrong packet msg");
ok(sprintf('%.6f', $h{'latitude'}), "55.744498", "wrong latitude");
ok(sprintf('%.6f', $h{'longitude'}), "37.685772", "wrong longitude");

