#!/usr/bin/perl

use inc::Module::Install;
name('Prophet');    #  App::Settings App::Settings::CLI App::WebToy App::WebToy::CLI

author('clkao and jesse');

license('mit');
requires('Exporter::Lite');
requires('Params::Validate');
requires('IPC::Run3');
requires('UUID::Tiny' => '1.02');
requires('Digest::SHA');
requires('LWP::UserAgent');     #  LWP::ConnCache too
requires('URI');
requires('HTTP::Date');
requires( 'JSON' => '2.00' );
requires('Module::Pluggable');
requires('Proc::InvokeEditor');
requires( 'Any::Moose'    => '0.04' );
requires( 'Mouse'         => '0.21' );
requires('XML::Atom::SimpleFeed');
requires( 'Path::Dispatcher' => '0.09' );    # Path::Dispatcher::Declarative
requires('Time::Progress');
requires('Config::GitLike' => '1.02');
requires('MIME::Base64::URLSafe');
if ( $^O =~ /MSWin/ ) {
    requires( 'Win32' );
}

build_requires( 'Test::Exception' => '0.26' );

use Term::ReadLine;                          # if we don't do this, ::Perl fails
feature 'Improved interactive shell' => -default => 1,
    'Term::ReadLine::Perl'           => 0;
feature 'Faster JSON Parsing' => -default => 1,
    'JSON::XS',               => '2.2222';
feature 'Web server' => -default => 1,
    'File::ShareDir' => '1.00',
    'HTTP::Server::Simple' => '0.40',                  # HTTP::Server::Simple::CGI
    ;
feature 'HTML display'  => -default => 1,
    'Template::Declare' => '0.35',  # Template::Declare::Tags
    ;
feature 'Foreign replica support' => -default => 1,
    'Term::ReadKey';
feature 'SQLite replica support' => -default => 1,
    'DBI'                        => 1,
    'DBD::SQLite'                => 1;

feature 'Maintainer testing tools' => -default => 1,
    'Test::HTTP::Server::Simple',
    'YAML::Syck'           => 0,
    'Module::Refresh'      => 0,
    'Test::WWW::Mechanize' => '1.16',
    'Test::Pod::Coverage';
feature 'Bonjour support' => -default => 0,
    'Net::Bonjour',    # Net::Rendezvous::Publish
    ;

tests('t/*.t t/*/t/*.t');
all_from('lib/Prophet.pm');
install_share 'share';
auto_install;
WriteAll();
