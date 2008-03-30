#!/usr/bin/perl
#
use inc::Module::Install;
requires('Params::Validate');
requires('Class::Accessor');
requires('Data::UUID');
requires('Path::Class');
requires('SVN::Core'); # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
all_from('lib/Prophet.pm');

WriteAll();
