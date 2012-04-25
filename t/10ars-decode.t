
use Test;
BEGIN { plan tests => 1 + 4 + 4 };
use TRBO::ARS;
ok(1); # If we made it this far, we're ok.

my $ars = new TRBO::ARS();

# port 4005 "i am here" from 1234567
my $msg = '000cf02007313233343536370000';
my $bin = pack('H*', $msg);
my %h;
my $retval = $ars->TRBO::ARS::decode(\%h, $bin);

ok($retval, 1, "failed to parse 'hello' packet from 1234567");
ok($h{'class'}, 'ars', "wrong packet class");
ok($h{'msg'}, 'hello', "wrong packet message for 'hello'");
ok($h{'id'}, '1234567', "wrong id parsed for 'hello' packet from 1234567");

# port 4005 "i am here" from 1235
$msg = '0009f02004313233350000';
$bin = pack('H*', $msg);
%h = ();
$retval = $ars->decode(\%h, $bin);

ok($retval, 1, "failed to parse 'hello' packet from 1235");
ok($h{'class'}, 'ars', "wrong packet class");
ok($h{'msg'}, 'hello', "wrong packet message for 'hello'");
ok($h{'id'}, '1235', "wrong id parsed for 'hello' packet from 1235");

