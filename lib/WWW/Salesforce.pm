package WWW::Salesforce;

use Mojo::Base 'Mojo::EventEmitter';
use Mojo::Date;
use Mojo::IOLoop;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;
use Mojo::UserAgent;

has '_api_path';
has '_ua';
has '_access_token';
has '_access_time';

# salesforce login attributes
has api_host => sub{ return Mojo::URL->new('https://login.salesforce.com/') };
has consumer_key => '';
has consumer_secret => '';
has username => '';
has password => '';
has pass_token => '';

# If we already know the latest API path, then use it, otherwise ask Salesforce
# for a list and parse that list to obtain the latest.
sub api_path {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	if ( my $path = $self->_api_path ) {
		return $path unless $cb;
		return $self->$cb($path);
	}
	unless ($cb) {
		my $tx = $self->ua->get( Mojo::URL->new($self->api_host)->path("/services/data"), $self->_headers() );
		return $self->_error( $tx->error->{code}, $tx->error->{message}, $tx->res->body ) unless $tx->success;
		return $self->_api_latest($tx->success->json);
	}
	return Mojo::IOLoop->delay(
		sub {
			$self->ua->get( Mojo::URL->new($self->api_host)->path("/services/data"), $self->_headers(), shift->begin(0) );
		},
		sub {
			my ($delay, $ua, $tx) = @_;
			return $self->$cb($self->_error($tx->error->{code}, $tx->error->{message}, $tx->res->body)) unless $tx->success;
			my $path = $self->_api_latest($tx->res->json);
			return $self->$cb(undef) unless $path;
			$self->_api_path($path);
			return $self->$cb($path);
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

# attempt a login to Salesforce to obtain a token
sub login {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;

	# force a new login on each call
	$self->_access_token(undef);

	my $url = Mojo::URL->new($self->api_host)->path("/services/oauth2/token");
	my $form = {
		grant_type => 'password',
		client_id => $self->consumer_key,
		client_secret => $self->consumer_secret,
		username => $self->username,
		password => $self->password . $self->pass_token,
	};

	# blocking request
	unless ($cb) {
		my $tx = $self->ua->post($url, $self->_headers(), form => $form);
		return $self->_error($tx->error->{code}, $tx->error->{message}, $tx->res->body) unless $tx->success;
		my $data = $tx->res->json;
		$self->api_host($data->{instance_url});
		$self->_access_token($data->{access_token});
		$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		$self->api_path(); # get the latest API path available to us
		return $self->_access_token;
	}

	# non-blocking request
	return Mojo::IOLoop->delay(
		sub { $self->ua->post($url, $self->_headers(), form => $form, shift->begin(0)); },
		sub {
			my ($delay, $ua, $tx) = @_;
			$self->_error( $tx->error->{code}, $tx->error->{message}, $tx->res->body ) unless $tx->success;
			my $data = $tx->res->json;
			$self->api_host($data->{instance_url});
			$self->_access_token($data->{access_token});
			$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
			$self->api_path( $delay->begin() );
		},
		sub {
			my ( $delay, $path ) = @_;
			return $self->$cb(undef) unless $path;
			return $self->$cb($self->_access_token);
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

sub query {
	my ($self, $query, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;

	# blocking request
	unless ( $cb ) {
		return [] unless $query;
		$self->_require_login(); # handles renewing the auth token if necessary
		my $results = [];
		my $url = Mojo::URL->new($self->api_host)->path($self->api_path)->path('query/');
		my $tx = $self->ua->get( $url, $self->_headers(), form => { q => $query, } );
		while(1) {
			$self->_error( $tx->error->{code}, $tx->error->{message}, $tx->res->body ) unless( $tx->success );
			my $json = $tx->success->json;
			push @{$results}, @{$json->{records}};

			last if $json->{done};
			last unless $json->{nextRecordsUrl};
			$self->_require_login();
			$url = Mojo::URL->new($self->api_host)->path($json->{nextRecordsUrl});
			$tx = $self->ua->get( $url, $self->_headers() );
		}
		return $results;
	}
	# non-blocking request
	return $self->$cb([]) unless $query;
	return Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			$self->_require_login( $delay->begin(0));
		},
		sub {
			my ( $delay, $token ) = @_;
			return $self->$cb([]) unless $token;
			my $url = Mojo::URL->new($self->api_host)->path($self->_api_path)->path('query/');
			$delay->data(self=>$self,cb=>$cb);
			$delay->steps(\&_query_results_nb);
			$self->ua->get($url, $self->_headers(), form => {q=>$query,}, $delay->begin(0) );
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

sub ua {
	my $self = shift;
	my $ua = $self->_ua;
	return $ua if $ua;
	$ua = Mojo::UserAgent->new(inactivity_timeout=>50);
	$ua->on('error' => sub {
		my ($e, $err) = @_;
		#catch and throw
		$self->emit(error=>$err);
	});
	$self->_ua($ua);
	return $ua;
}

# parse through the API path results to select the latest available API version.
sub _api_latest {
	my ($self,$data) = @_;
	return undef unless $data && ref($data) && ref($data) eq 'ARRAY';
	my $highest = 0;
	my $final_path;
	for my $row ( @{$data} ) {
		my $num = int($row->{version} // 0);
		my $path = $row->{url} // '';
		next unless $path && $num > $highest;
		$highest = $num;
		$path .= '/' unless substr($path,-1,1) eq '/';
		$final_path = $path;
	}
	return $final_path;
}

# emit an error
sub _error {
	my ( $self, $code, $msg, $body ) = @_;
	$code ||= 500;
	$msg ||= '';
	$body ||= '';
	$self->emit(error=>"ERROR: $code, $msg: $body");
	return undef;
}

# Get the headers we need to send each time
sub _headers {
	my $self = shift;
	my $header = {
		Accept => 'application/json',
		DNT => 1,
		Date => Mojo::Date->new()->to_string(),
		'Sforce-Query-Options' => 'batchSize=2000',
		'Accept-Charset' => 'UTF-8',
	};
	return $header unless my $token = $self->_access_token;
	$header->{'Authorization'} = "Bearer $token";
	return $header;
}

sub _query_results_nb {
	my ($delay, $ua, $tx ) = @_;
	my $self = $delay->data('self') || die "Can't find SF object";
	my $cb = $delay->data('cb') || die "Can't find CallBack";
	return $self->_error( $tx->error->{code}, $tx->error->{message}, $tx->res->body ) unless $tx->success;
	my $data = $tx->res->json;
	my $records = $delay->data('records') || [];
	push @{$records}, @{$data->{records}};
	$delay->data(records=>$records);
	return $self->$cb($records) if $data->{done};
	return $self->$cb($records) unless $data->{nextRecordsUrl};
	my $url = Mojo::URL->new($self->api_host)->path($data->{nextRecordsUrl});
	$delay->steps(\&_query_results_nb);
	$self->ua->get($url, $self->_headers(), $delay->begin(0) );
}

# run this on every API call to ensure we stay logged in as tokens time out
sub _require_login {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	if( $self->_access_token ) {
		if ( my $time = $self->_access_time ) {
			if ( int((time() - $time)/60) < 30 ) {
				# we should be good at this point.
				return $self->_access_token unless $cb;
				return $self->$cb($self->_access_token);
			}
		}
	}
	# aww crap, we need to login.
	return $self->login() unless $cb;
	return Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			$self->login($delay->begin(0));
		},
		sub {
			my ($delay, $sf, $token) = @_;
			return $sf->$cb($token);
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

1;
