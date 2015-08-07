use 5.010001;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => 'WWW::Salesforce',
	AUTHOR => q{Chase Whitener <cwhitener@gmail.com>},
	VERSION_FROM => 'lib/WWW/Salesforce.pm',
	ABSTRACT_FROM => 'lib/WWW/Salesforce.pm',
	LICENSE => 'artistic_2',
	META_MERGE => {
		requires  => {perl => '5.010001'},
		resources => {
			license    => 'http://www.opensource.org/licenses/artistic-license-2.0',
			homepage => 'https://github.com/genio/www-salesforce-nb',
			bugtracker => 'https://github.com/genio/www-salesforce-nb/issues',
			repository => 'https://github.com/genio/www-salesforce-nb.git',
		},
		no_index => {directory => ['t']}
	},
	BUILD_REQUIRES => {
		'Test::More' => 0,
		'Test::Pod' => 0,
		'Test::Pod::Coverage' => 0,
	},
	PREREQ_PM => {
		'IO::Socket::IP' => 0.20,
		'IO::Socket::Socks' => 0.64,
		'IO::Socket::SSL' => 1.84,
		'Mojolicious' => 5.24,
		'POSIX' => 0.0,
		'utf8' => 0.0,
	},
	test => {TESTS => 't/*.t'},
);
