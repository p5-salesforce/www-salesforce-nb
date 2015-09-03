use 5.010001;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => 'WWW::Salesforce',
	VERSION_FROM => 'lib/WWW/Salesforce.pm',
	ABSTRACT => 'A non-blocking Perl Salesforce client',
	AUTHOR => q{Chase Whitener <cwhitener@gmail.com>},
	LICENSE => 'artistic_2',
	META_MERGE => {
		dynamic_config => 0,
		'meta-spec' => {version=>2},
		no_index => {directory => ['t']},
		prereqs => {runtime => {requires => {perl => '5.010001'}}},
		resources => {
			bugtracker => {web=>'https://github.com/genio/www-salesforce-nb/issues'},
			homepage => 'https://github.com/genio/www-salesforce-nb',
			license => ['http://www.opensource.org/licenses/artistic-license-2.0'],
			repository => {
				type => 'git',
				url => 'https://github.com/genio/www-salesforce-nb.git',
				web => 'https://github.com/genio/www-salesforce-nb',
			},
			X_IRC => 'irc://irc.perl.org/#perl',
		},
	},
	BUILD_REQUIRES => {
		'Test::More' => 0,
		'Test::Pod' => 0,
		'Test::Pod::Coverage' => 0,
		'Try::Tiny' => 0,
	},
	PREREQ_PM => {
		'IO::Socket::IP' => 0.20,
		'IO::Socket::Socks' => 0.64,
		'IO::Socket::SSL' => 1.84,
		'Mojolicious' => 5.24,
		'Moo' => 0.0,
		'namespace::clean' => 0.0,
		'POSIX' => 0.0,
		'strictures' => 2.0,
		'utf8' => 0.0,
	},
	test => {TESTS => 't/*.t'},
);
