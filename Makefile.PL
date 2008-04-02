#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet');
author('clkao and jesse');
license('Death and Repudiation');
requires('Params::Validate');
requires('Class::Accessor');
requires('IPC::Run3');
requires('Test::Exception');
requires('Data::UUID');
requires('Path::Class');
requires('YAML::Syck');
requires('Acme::MetaSyntactic');
requires('UNIVERSAL::require');

requires('SVN::Core'); # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
all_from('lib/Prophet.pm');

WriteAll();
