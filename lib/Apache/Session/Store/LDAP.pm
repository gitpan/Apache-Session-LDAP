#############################################################################
#
# Apache::Session::Store::DB_File
# Implements session object storage via Perl's DB_File module
# Copyright(c) 2000 Jeffrey William Baker (jwbaker@acm.org)
# Distribute under the Perl License
#
############################################################################

package Apache::Session::Store::LDAP;

use strict;
use vars qw($VERSION);
use Net::LDAP;

$VERSION = '1.01';

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub insert {
    my $self    = shift;
    my $session = shift;
    $self->{args} = $session->{args};
    
    my $msg = $self->ldap->add(
        "cn=$session->{data}->{_session_id},".$self->{args}->{ldapConfBase},
        attrs => [
        objectClass => [ 'top', 'applicationProcess' ],
        cn => $session->{data}->{_session_id},
        description => $session->{serialized},
        ],
    );
    $self->logError($msg) if ( $msg->code );
}

sub update {
    my $self = shift;
    my $session = shift;
    $self->{args} = $session->{args};
    
    my $msg = $self->ldap->modify(
        "cn=$session->{data}->{_session_id},".$self->{args}->{ldapConfBase},
        replace => {
            description => $session->{serialized},
        },
    );
    
    $self->logError($msg) if ($msg->code);
}

sub materialize {
    my $self = shift;
    my $session = shift;
    $self->{args} = $session->{args};
    
    my $msg = $self->ldap->search(
        base => "cn=$session->{data}->{_session_id},".$self->{args}->{ldapConfBase},
        filter => '(objectClass=applicationProcess)',
        scope  => 'base',
        attrs  => ['description'],
    );
    
    $self->logError($msg) if ( $msg->code );

    eval {$session->{serialized} = $msg->shift_entry()->get_value('description');};

    if (!defined $session->{serialized}) {
        die "Object does not exist in data store";
    }
}

sub remove {
    my $self = shift;
    my $session = shift;
    $self->{args} = $session->{args};
    
    $self->ldap->delete("cn=$session->{data}->{_session_id},".$self->{args}->{ldapConfBase});
}

sub ldap {
    my $self = shift;
    return $self->{ldap} if($self->{ldap});

    # Parse servers configuration
    my $useTls = 0;
    my $tlsParam;
    my @servers = ();
    #print STDERR Dumper($self);exit;use Data::Dumper;
    foreach my $server ( split /[\s,]+/, $self->{args}->{ldapServer} ) {
        if ( $server =~ m{^ldap\+tls://([^/]+)/?\??(.*)$} ) {
            $useTls   = 1;
            $server   = $1;
            $tlsParam = $2 || "";
        }
        else {
            $useTls = 0;
        }
        push @servers, $server;
    }

    # Connect
    my $ldap = Net::LDAP->new(
        \@servers,
        onerror => undef,
        ( $self->{args}->{ldapPort} ? ( port => $self->{args}->{ldapPort} ) : () ),
    ) or die('Unable to connect to '.join(' ',@servers));

    # Start TLS if needed
    if ($useTls) {
        my %h = split( /[&=]/, $tlsParam );
        $h{cafile} = $self->{args}->{caFile} if ( $self->{args}->{caFile} );
        $h{capath} = $self->{args}->{caPath} if ( $self->{args}->{caPath} );
        my $start_tls = $ldap->start_tls(%h);
        if ( $start_tls->code ) {
            $self->logError($start_tls);
            return;
        }
    }

    # Bind with credentials
    my $bind =
      $ldap->bind( $self->{args}->{ldapBindDN}, password => $self->{args}->{ldapBindPassword} );
    if ( $bind->code ) {
        $self->logError($bind);
        return;
    }

    $self->{ldap} = $ldap;
    return $ldap;
}

sub logError {
    my $self           = shift;
    my $ldap_operation = shift;
    die "LDAP error " . $ldap_operation->code . ": " . $ldap_operation->error;
}


1;

=pod

=head1 NAME

Apache::Session::Store::DB_File - Use DB_File to store persistent objects

=head1 SYNOPSIS

 use Apache::Session::Store::DB_File;

 my $store = new Apache::Session::Store::DB_File;

 $store->insert($ref);
 $store->update($ref);
 $store->materialize($ref);
 $store->remove($ref);

=head1 DESCRIPTION

This module fulfills the storage interface of Apache::Session.  The serialized
objects are stored in a Berkeley DB file using the DB_File Perl module.  If
DB_File works on your platform, this module should also work.

=head1 OPTIONS

This module requires one argument in the usual Apache::Session style.  The
name of the option is FileName, and the value is the full path of the database
file to be used as the backing store.  If the database file does not exist,
it will be created.  Example:

 tie %s, 'Apache::Session::DB_File', undef,
    {FileName => '/tmp/sessions'};

=head1 AUTHOR

This module was written by Jeffrey William Baker <jwbaker@acm.org>.

=head1 SEE ALSO

L<Apache::Session>, L<DB_File>
