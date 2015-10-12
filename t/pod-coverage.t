use strict;
use Test::More;
use Test::Pod::Coverage;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
	unless $ENV{TEST_POD};

plan tests => 2;
pod_coverage_ok( "WWW::Salesforce" );
pod_coverage_ok( "WWW::Salesforce::SOAP" );
