Short script to iterate through a root directory looking for split-volume archives, and then extract them in place.

An ideal scenario would be something akin to:

~/movies/movie.a.2016
    a.nfo
    a.rar
    a.r01
    a.r02 
~/movies/movie.b.2020
    b.nfo
    b.rar
    b.r01
....

and so on. 

Roadmap: 
    -Parse command line argument, i.e `./mass_extract.pl /home/me/new_movies_batch` 
    -Command line argument to put the extracted files in a centralized location, i.e `./mass_extract.pl /home/me/downloads -o /home/me/movies`
    -Command line argument to delete the original folder after that rars are extracted.
    -Check integrity of the extracted files.
    -Small log of everything that happened.


This probably should have been in bash!
