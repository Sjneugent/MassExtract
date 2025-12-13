package MassExtractGUI;

use strict;
use warnings;
use Tk;
use Tk::ProgressBar;
use File::Basename;

=head1 NAME

MassExtractGUI - Graphical user interface for Mass RAR Extractor

=head1 DESCRIPTION

This module provides the Tk-based GUI interface for the mass extraction tool,
including options window and progress window with real-time output display.

=cut

=head2 new()

Creates a new MassExtractGUI instance.

=cut

sub new {
    my ($class) = @_;
    
    my $self = {
        options => {},
        progress_window => undef,
        progress_bar => undef,
        progress_label => undef,
        output_text => undef,
        close_button => undef,
        progress_value => 0,
        total_dirs => 0,
        current_dir_index => 0,
    };
    
    return bless $self, $class;
}

=head2 show_options_dialog()

Displays the options configuration dialog.

B<Returns:> Hash with keys: root_dir, output_dir, delete_after, log_file
Returns undef if user cancels.

=cut

sub show_options_dialog {
    my ($self) = @_;
    
    my %options;
    my $completed = 0;
    
    my $mw = MainWindow->new;
    $mw->title("Mass RAR Extractor Options");
    
    # Root directory selection (required)
    $mw->Label(-text => "Select Root Directory:")->pack();
    my $root_entry = $mw->Entry(-width => 50);
    $root_entry->pack();
    $mw->Button(
        -text => "Browse",
        -command => sub {
            my $dir = $mw->chooseDirectory(-title => "Select Root Directory");
            if (defined $dir) {
                $root_entry->delete(0, 'end');
                $root_entry->insert(0, $dir);
            }
        }
    )->pack();
    
    # Output directory selection (optional)
    $mw->Label(-text => "Select Output Directory (optional):")->pack();
    my $output_entry = $mw->Entry(-width => 50);
    $output_entry->pack();
    $mw->Button(
        -text => "Browse",
        -command => sub {
            my $dir = $mw->chooseDirectory(-title => "Select Output Directory");
            if (defined $dir) {
                $output_entry->delete(0, 'end');
                $output_entry->insert(0, $dir);
            }
        }
    )->pack();
    
    # Delete after extraction checkbox
    my $delete_var = 0;
    $mw->Checkbutton(
        -text => "Delete RAR files after extraction",
        -variable => \$delete_var
    )->pack();
    
    # Log file selection (optional)
    $mw->Label(-text => "Log File (optional):")->pack();
    my $log_entry = $mw->Entry(-width => 50);
    $log_entry->pack();
    $mw->Button(
        -text => "Browse",
        -command => sub {
            my $file = $mw->getSaveFile(
                -title => "Select Log File",
                -defaultextension => '.csv',
                -filetypes => [['CSV Files', '.csv'], ['All Files', '.*']]
            );
            if (defined $file) {
                $log_entry->delete(0, 'end');
                $log_entry->insert(0, $file);
            }
        }
    )->pack();
    
    # Start button
    $mw->Button(
        -text => "Start Extraction",
        -command => sub {
            $options{root_dir} = $root_entry->get();
            $options{output_dir} = $output_entry->get();
            $options{delete_after} = $delete_var;
            $options{log_file} = $log_entry->get();
            $completed = 1;
            $mw->destroy();
        }
    )->pack();
    
    MainLoop;
    
    return $completed ? %options : undef;
}

=head2 create_progress_window($total_dirs)

Creates and displays the extraction progress window.

B<Parameters:>

=over 4

=item $total_dirs - Total number of directories to process

=back

=cut

sub create_progress_window {
    my ($self, $total_dirs) = @_;
    
    $self->{total_dirs} = $total_dirs;
    $self->{current_dir_index} = 0;
    
    $self->{progress_window} = MainWindow->new;
    $self->{progress_window}->title("Mass RAR Extractor - Progress");
    $self->{progress_window}->geometry("700x500");
    
    # Progress label
    $self->{progress_label} = $self->{progress_window}->Label(
        -text => "Initializing...",
        -font => [-size => 10, -weight => 'bold']
    )->pack(-pady => 10, -padx => 10, -fill => 'x');
    
    # Progress bar
    $self->{progress_bar} = $self->{progress_window}->ProgressBar(
        -width => 30,
        -length => 650,
        -from => 0,
        -to => 100,
        -variable => \$self->{progress_value},
        -colors => [0, 'blue']
    )->pack(-pady => 10, -padx => 10);
    
    # Output text widget
    my $output_frame = $self->{progress_window}->Frame()->pack(
        -fill => 'both',
        -expand => 1,
        -padx => 10,
        -pady => 5
    );
    $output_frame->Label(-text => "Extraction Output:")->pack(-anchor => 'w');
    
    $self->{output_text} = $output_frame->Scrolled(
        'Text',
        -scrollbars => 'e',
        -height => 20,
        -width => 80,
        -font => ['Courier', 9],
        -state => 'normal',
        -wrap => 'word'
    )->pack(-fill => 'both', -expand => 1);
    
    # Close button (initially disabled)
    $self->{close_button} = $self->{progress_window}->Button(
        -text => "Close",
        -state => 'disabled',
        -command => sub { $self->{progress_window}->destroy(); }
    )->pack(-pady => 10);
    
    $self->{progress_window}->update();
}

=head2 update_progress($message, $percent)

Updates the progress window with new status information.

B<Parameters:>

=over 4

=item $message - (optional) New text for the progress label

=item $percent - (optional) New progress percentage (0-100)

=back

=cut

sub update_progress {
    my ($self, $message, $percent) = @_;
    
    return unless $self->{progress_window};
    
    if (defined $message) {
        $self->{progress_label}->configure(-text => $message);
    }
    
    if (defined $percent) {
        $self->{progress_value} = $percent;
    }
    
    $self->{progress_window}->update();
}

=head2 update_directory_progress($dir_index, $dir_name)

Updates progress based on current directory being processed.

B<Parameters:>

=over 4

=item $dir_index - Current directory index (0-based)

=item $dir_name - Name of directory being processed

=back

=cut

sub update_directory_progress {
    my ($self, $dir_index, $dir_name) = @_;
    
    $self->{current_dir_index} = $dir_index;
    
    my $percent = 0;
    if ($self->{total_dirs} > 0) {
        $percent = ($dir_index / $self->{total_dirs}) * 100;
    }
    
    my $message = sprintf(
        "Processing (%d/%d): %s",
        $dir_index,
        $self->{total_dirs},
        basename($dir_name)
    );
    
    $self->update_progress($message, $percent);
}

=head2 append_output($text)

Appends text to the output display widget.

B<Parameters:>

=over 4

=item $text - The text to append

=back

=cut

sub append_output {
    my ($self, $text) = @_;
    
    return unless $self->{output_text};
    
    $self->{output_text}->insert('end', $text);
    $self->{output_text}->see('end');
    $self->{progress_window}->update();
}

=head2 enable_close_button()

Enables the close button when extraction is complete.

=cut

sub enable_close_button {
    my ($self) = @_;
    
    return unless $self->{close_button};
    
    $self->{close_button}->configure(-state => 'normal');
    $self->{progress_window}->update();
}

=head2 show_completion_dialog($message)

Shows a simple completion message dialog.

B<Parameters:>

=over 4

=item $message - Message to display

=back

=cut

sub show_completion_dialog {
    my ($self, $message) = @_;
    
    my $msg_win = MainWindow->new;
    $msg_win->title("Mass RAR Extractor - Complete");
    $msg_win->Label(
        -text => $message,
        -justify => 'center'
    )->pack(-padx => 20, -pady => 15);
    $msg_win->Button(
        -text => "OK",
        -width => 10,
        -command => sub { $msg_win->destroy(); }
    )->pack(-pady => 10);
    $msg_win->update();
    MainLoop;
}

=head2 main_loop()

Enters the Tk main event loop.

=cut

sub main_loop {
    my ($self) = @_;
    MainLoop;
}

1;

__END__

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.
