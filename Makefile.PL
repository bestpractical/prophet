#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet'); #  App::Settings App::Settings::CLI App::WebToy App::WebToy::CLI
author('clkao and jesse');
license('Perl');

requires('Params::Validate');
requires('IPC::Run3');
requires('Data::UUID');
requires('Digest::SHA1');  # Core in 5.10
requires('LWP::Simple'); # Part of lib-www-perl
requires('URI');
requires('HTTP::Date');
requires('JSON' => '2.00');
requires('Module::Pluggable');
requires('File::Find::Rule');
requires('Proc::InvokeEditor');
requires('Scalar::Defer' => '0.18');
requires('Any::Moose' => '0.03');
requires('Mouse' => '0.16');
requires('XML::Atom::SimpleFeed');
requires('Path::Dispatcher' => '0.09'); # Path::Dispatcher::Declarative
requires('Time::Progress');

build_requires('Test::Exception' => '0.26');

use Term::ReadLine; # if we don't do this, ::Perl fails
features(
    'Improved interactive shell' => [
        -default => 1,
        'Term::ReadLine::Perl'
        ],
    'Faster JSON Parsing' => [
        -default => 1,
        'JSON::XS', => '2.2222'
    ],
    'Web server' => [
        -default => 1,
        'File::ShareDir' => '1.00',
        'HTTP::Server::Simple', # HTTP::Server::Simple::CGI
    ],

    'HTML display' => [
        -default => 1,
        'Template::Declare' => '0.35', # Template::Declare::Tags
    ],
    'Foreign replica support' => [
        -default => 1,
        'Term::ReadKey'
    ],
    'SQLite replica support' => [
        -default => 1,
        'DBI' => 1,
        'DBD::SQLite' => 1
    ],
    'Maintainer testing tools' => [
        -default   => 1,
        'Test::HTTP::Server::Simple',
        'YAML::Syck' => 0,
        'Module::Refresh' => 0,
        'Test::WWW::Mechanize' => '1.16',
        'Test::Pod::Coverage'
    ],
#    q{Devel::Gladiator support (contact sky@crucially.net if it's not on CPAN)} => [
#        -default => 0,
#        'Devel::Gladiator'
#    ],
    'Bonjour support' => [
        -default => 0,
        'Net::Bonjour', # Net::Rendezvous::Publish
    ],
);

tests('t/*.t t/*/t/*.t');
all_from('lib/Prophet.pm'); 
install_script('bin/prophet');
install_share 'share';
auto_install;
WriteAll();
