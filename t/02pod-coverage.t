
# Test POD documentation coverage

use Test::More;
eval "use Test::Pod::Coverage";
plan skip_all => "Test::Pod::Coverage required for testing pod coverage" if $@;

plan tests => 4;
pod_coverage_ok("TRBO::NET");
pod_coverage_ok("TRBO::ARS");
pod_coverage_ok("TRBO::LOC");
pod_coverage_ok("TRBO::TMS");

