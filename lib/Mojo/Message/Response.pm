package Mojo::Message::Response;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Response;
use Mojo::Date;
use Mojo::Util 'get_line';

has [qw/code message/];

# Start line regex
my $START_LINE_RE = qr/
  ^\s*
  HTTP\/(\d\.\d)   # Version
  \s+
  (\d\d\d)         # Code
  \s*
  ([\w\'\s]+)?     # Message (with "I'm a teapot" support)
  $
/x;

# Umarked codes are from RFC 2616 (mostly taken from LWP)
my %MESSAGES = (
  100 => 'Continue',
  101 => 'Switching Protocols',
  102 => 'Processing',                      # RFC 2518 (WebDAV)
  200 => 'OK',
  201 => 'Created',
  202 => 'Accepted',
  203 => 'Non-Authoritative Information',
  204 => 'No Content',
  205 => 'Reset Content',
  206 => 'Partial Content',
  207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
  300 => 'Multiple Choices',
  301 => 'Moved Permanently',
  302 => 'Found',
  303 => 'See Other',
  304 => 'Not Modified',
  305 => 'Use Proxy',
  307 => 'Temporary Redirect',
  400 => 'Bad Request',
  401 => 'Unauthorized',
  402 => 'Payment Required',
  403 => 'Forbidden',
  404 => 'Not Found',
  405 => 'Method Not Allowed',
  406 => 'Not Acceptable',
  407 => 'Proxy Authentication Required',
  408 => 'Request Timeout',
  409 => 'Conflict',
  410 => 'Gone',
  411 => 'Length Required',
  412 => 'Precondition Failed',
  413 => 'Request Entity Too Large',
  414 => 'Request-URI Too Large',
  415 => 'Unsupported Media Type',
  416 => 'Request Range Not Satisfiable',
  417 => 'Expectation Failed',
  418 => "I'm a teapot",                    # :)
  422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
  423 => 'Locked',                          # RFC 2518 (WebDAV)
  424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
  425 => 'Unordered Colection',             # RFC 3648 (WebDav)
  426 => 'Upgrade Required',                # RFC 2817
  449 => 'Retry With',                      # unofficial Microsoft
  500 => 'Internal Server Error',
  501 => 'Not Implemented',
  502 => 'Bad Gateway',
  503 => 'Service Unavailable',
  504 => 'Gateway Timeout',
  505 => 'HTTP Version Not Supported',
  506 => 'Variant Also Negotiates',         # RFC 2295
  507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
  509 => 'Bandwidth Limit Exceeded',        # unofficial
  510 => 'Not Extended'                     # RFC 2774
);

sub cookies {
  my $self = shift;

  # Add cookies
  if (@_) {
    for my $cookie (@_) {
      $cookie = Mojo::Cookie::Response->new($cookie)
        if ref $cookie eq 'HASH';
      $self->headers->add('Set-Cookie', "$cookie");
    }
    return $self;
  }

  # Set-Cookie2
  my @cookies;
  my $headers = $self->headers;
  push @cookies, @{Mojo::Cookie::Response->parse($_)}
    for $headers->set_cookie2;

  # Set-Cookie
  push @cookies, @{Mojo::Cookie::Response->parse($_)}
    for $headers->set_cookie;

  return \@cookies;
}

sub default_message { $MESSAGES{$_[1] || $_[0]->code || 404} || '' }

sub fix_headers {
  my $self = shift;
  $self->SUPER::fix_headers(@_);

  # Date header is required in responses
  my $headers = $self->headers;
  $headers->date(Mojo::Date->new->to_string) unless $headers->date;

  return $self;
}

sub is_status_class {
  my ($self, $class) = @_;
  return unless my $code = $self->code;
  return 1 if $code >= $class && $code < ($class + 100);
  return;
}

sub _build_start_line {
  my $self = shift;

  # HTTP 0.9 has no start line
  my $version = $self->version;
  return '' if $version eq '0.9';

  # HTTP 1.0 and above
  my $code    = $self->code    || 404;
  my $message = $self->message || $self->default_message;
  return "HTTP/$version $code $message\x0d\x0a";
}

# "Weaseling out of things is important to learn.
#  It's what separates us from the animals... except the weasel."
sub _parse_start_line {
  my $self = shift;

  # HTTP 0.9 responses have no start line
  return $self->{state} = 'content' if $self->version eq '0.9';

  # Try to detect HTTP 0.9
  if ($self->{buffer} =~ /^\s*(\S+\s*)/) {
    my $string = $1;

    # HTTP 0.9 will most likely not start with "HTTP/"
    my $match = "\/PTTH";
    substr $match, 0, 5 - length $string, '' if length $string < 5;
    $match = reverse $match;

    # Detected!
    if ($string !~ /^\s*$match/) {
      $self->version('0.9');
      $self->{state} = 'content';
      $self->content->relaxed(1);
      return 1;
    }
  }

  # We have a full HTTP 1.0+ response line
  my $line = get_line $self->{buffer};
  if (defined $line) {
    if ($line =~ m/$START_LINE_RE/o) {
      $self->version($1);
      $self->code($2);
      $self->message($3);
      $self->{state} = 'content';
      $self->content->auto_relax(1);
    }
    else { $self->error('Bad response start line.') }
  }
}

1;
__END__

=head1 NAME

Mojo::Message::Response - HTTP 1.1 response container

=head1 SYNOPSIS

  use Mojo::Message::Response;

  # Parse
  my $res = Mojo::Message::Reponse->new;
  $res->parse("HTTP/1.0 200 OK\x0a\x0d");
  $res->parse("Content-Length: 12\x0a\x0d\x0a\x0d");
  $res->parse("Content-Type: text/plain\x0a\x0d\x0a\x0d");
  $res->parse('Hello World!');
  print $res->body;

  # Build
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Hello World!');
  print $res->to_string;

=head1 DESCRIPTION

L<Mojo::Message::Response> is a container for HTTP 1.1 responses as described
in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Message::Response> inherits all attributes from L<Mojo::Message>
and implements the following new ones.

=head2 C<code>

  my $code = $res->code;
  $res     = $res->code(200);

HTTP response code.

=head2 C<message>

  my $message = $res->message;
  $res        = $res->message('OK');

HTTP response message.

=head1 METHODS

L<Mojo::Message::Response> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<cookies>

  my $cookies = $res->cookies;
  $res        = $res->cookies(Mojo::Cookie::Response->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access response cookies, usually L<Mojo::Cookie::Response> objects.

=head2 C<default_message>

  my $message = $res->default_message;

Generate default response message for code.

=head2 C<fix_headers>

  $res = $res->fix_headers;

Make sure message has all required headers for the current HTTP version.

=head2 C<is_status_class>

  my $is_2xx = $res->is_status_class(200);

Check response status class.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
