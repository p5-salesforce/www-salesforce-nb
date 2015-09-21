use Mojolicious::Lite;
use Data::Dumper;
BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# Silence
app->log->level('fatal');
get '/' => {text => 'works!'};
get '/services/data/v33.0/sobjects' => sub {
	my $c = shift;
	return $c->render(json=>{
		encoding => "UTF-8",
		maxBatchSize => 200,
		sobjects => [
			{
				activateable => 'false',
				createable => 'true',
				custom => 'false',
				customSetting => 'false',
				deletable => 'true',
				deprecatedAndHidden => 'false',
				feedEnabled => 'true',
				keyPrefix => "001",
				label => "Account",
				labelPlural => "Accounts",
				layoutable => 'true',
				mergeable => 'true',
				name => "Account",
				queryable => 'true',
				replicateable => 'true',
				retrieveable => 'true',
				searchable => 'true',
				triggerable => 'true',
				undeletable => 'true',
				updateable => 'true',
				urls => {
					compactLayouts => "/services/data/v34.0/sobjects/Account/describe/compactLayouts",
					rowTemplate => "/services/data/v34.0/sobjects/Account/{ID}",
					approvalLayouts => "/services/data/v34.0/sobjects/Account/describe/approvalLayouts",
					listviews => "/services/data/v34.0/sobjects/Account/listviews",
					describe => "/services/data/v34.0/sobjects/Account/describe",
					quickActions => "/services/data/v34.0/sobjects/Account/quickActions",
					layouts => "/services/data/v34.0/sobjects/Account/describe/layouts",
					sobject => "/services/data/v34.0/sobjects/Account",
				},
			},
		],
	});
};
post '/services/data/v33.0/sobjects/:type' => sub {
	my $c = shift;
	my $type = $c->stash('type');
	my $params = $c->req->json;
	return $c->render(json=>{success=>'false',id=>undef,errors=>['bad object']},status=>500) unless $type;
	return $c->render(json=>{success=>'false',id=>undef,errors=>['no params']},status=>500) unless $params && ref($params) eq 'HASH';
	return $c->render(json=>{success=>'false',id=>undef,errors=>['bad object']}) unless $type eq 'Account';
	return $c->render(json=>{success=>'true',id=>'01t500000016RuaAAE',errors=>[]});
};
get '/services/data/v33.0/query' => sub {
	my $c = shift;
	my $query = $c->param('q');
	if ( $query eq 'select Id,IsActive,Name from Product2' ) {
		return $c->render(json => {done=>0,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>[
			{
				Id=>'01t500000016RuaAAE',
				IsActive=>1,
				Name=>'Test Name',
				attributes=>{
					type=>'Product2',
					url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAE',
				},
			},
		],});
	}
	$c->render(json=>[{errorCode=>'foo',message=>'what?!?'}], status=>401);
};
get '/services/data/v33.0/query/test123' => sub {
	my $c = shift;
	return $c->render(json => {done=>1,records=>[
		{
			Id=>'01t500000016RuaAAF',
			IsActive=>1,
			Name=>'Test Name 2',
			attributes=>{
				type=>'Product2',
				url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAF',
			},
		},
	],});
};
post '/services/Soap/u/33.0/' => sub {
	my $c = shift;
	my $username = '';
	my $password = '';
	my $input = '';
	$input = $c->req->dom() if $c->req && $c->req->content && $c->req->dom;
	my $eof = q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>soapenv:Client</faultcode><faultstring>Premature end of file.</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>);
	return $c->render(data=>$eof, format => 'xml', status=>500) unless $input;
	$username = $input->at('urn\:username')->text() if $input->at('urn\:username');
	$password = $input->at('urn\:password')->text() if $input->at('urn\:password');
	#return actual error messages
	my $error=q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_LOGIN</faultcode><faultstring>INVALID_LOGIN: Invalid username, password, security token; or user locked out.</faultstring><detail><sf:LoginFault xsi:type="sf:LoginFault"><sf:exceptionCode>INVALID_LOGIN</sf:exceptionCode><sf:exceptionMessage>Invalid username, password, security token; or user locked out.</sf:exceptionMessage></sf:LoginFault></detail></soapenv:Fault></soapenv:Body></soapenv:Envelope>);
	return $c->render(data=>$error, format => 'xml', status=>500) unless $username eq 'test';
	return $c->render(data=>$error, format => 'xml', status=>500) unless $password eq 'testtoke';
	# return the successful response
	my $success=qq(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><loginResponse><result><metadataServerUrl>/</metadataServerUrl><passwordExpired>false</passwordExpired><sandbox>false</sandbox><serverUrl>/</serverUrl><sessionId>123455663452abacbabababababababanenenenene</sessionId><userId>00e30658AA0de34AA2</userId><userInfo><accessibilityMode>false</accessibilityMode><currencySymbol>\$</currencySymbol><orgAttachmentFileSizeLimit>5242880</orgAttachmentFileSizeLimit><orgDefaultCurrencyIsoCode>USD</orgDefaultCurrencyIsoCode><orgDisallowHtmlAttachments>false</orgDisallowHtmlAttachments><orgHasPersonAccounts>false</orgHasPersonAccounts><organizationId>00e30658AA0de34AAX</organizationId><organizationMultiCurrency>false</organizationMultiCurrency><organizationName>Test Company</organizationName><profileId>00e30658AA0de34AAA</profileId><roleId>00e30658AA0de34AA1</roleId><sessionSecondsValid>14400</sessionSecondsValid><userDefaultCurrencyIsoCode xsi:nil="true"/><userEmail>test\@tester.com</userEmail><userFullName>Test User</userFullName><userId>00e30658AA0de34AA2</userId><userLanguage>en_US</userLanguage><userLocale>en_US</userLocale><userName>$username</userName><userTimeZone>America/New_York</userTimeZone><userType>Standard</userType><userUiSkin>Theme3</userUiSkin></userInfo></result></loginResponse></soapenv:Body></soapenv:Envelope>);
	return $c->render(data => $success, format => 'xml');
};
post '/services/oauth2/revoke' => sub {
	my $c = shift;
	my $token = $c->param('token');
	return $c->render(json=>[{error_description=>"invalid token: $token",error=>"unsupported_token_type"}], status=>400) unless $token eq '123455663452abacbabababababababanenenenene';
	return $c->render(json=>[{success=>'true'}]);
};
post '/services/oauth2/token' => sub {
	my $c = shift;
	my $grant_type = $c->param('grant_type') || '';
	my $client_id = $c->param('client_id') || '';
	my $client_secret = $c->param('client_secret') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	#return actual error messages
	return $c->render(json=>[{error_description=>"grant type not supported",error=>"unsupported_grant_type"}], status=>400) unless $grant_type eq 'password';
	return $c->render(json=>[{error_description=>'Invalid client credentials',error=>'invalid_client'}], status=>400) unless $client_id eq 'test_id';
	return $c->render(json=>[{error_description=>'Invalid client credentials',error=>'invalid_client'}], status=>400) unless $client_secret eq 'test_secret';
	return $c->render(json=>[{error_description=>'authentication failure',error=>'invalid_grant'}], status=>400) unless $username eq 'test';
	return $c->render(json=>[{error_description=>'authentication failure',error=>"invalid_grant"}], status=>400) unless $password eq 'testtoke';
	# return the successful response
	return $c->render(json => {
		id => "/id/00D3012300VnRVAU/0015004310HWV5ZAQ",
		token_type =>"Bearer",
		signature => "CtSomeSignature3421351345141LKJFSDLK8723451nhx8=",
		instance_url => Mojo::URL->new('/'),
		issued_at => time()*1000,
		access_token => '123455663452abacbabababababababanenenenene'
	});
};
app->start;
