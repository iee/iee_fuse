/*
    Copyright (C) 2012 Andreas Baumann <abaumann@yahoo.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

int main( void )
{
	char buf[4096];
	int fd;
	int res;
	ssize_t wres;
	struct stat s;

	/* Make sure no file is around from last invocation */
	(void)unlink( "./mnt/testopen" );
	
	/* This should succeed */
	fd = open( "./mnt/testopen", O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR );
	if( fd < 0 ) {
		perror( "Unable to create testopen" );
		return 1;
	}

	/* write some data into it so we know if truncate really works */
	memset( buf, 0, 4096 );

	wres = write( fd, buf, 4096 );
	if( wres != 4096 ) {
		perror( "Error writing" );
		(void)close( fd );
		return 1;
	}
	
	(void)close( fd );

	/* check if the file has size 4096 */
	res = stat( "./mnt/testopen", &s );
	if( res < 0 ) {
		perror( "Error stating testopen" );
		return 1;
	}
	if( s.st_size == 4096 ) {
		// OK
	} else {
		fprintf( stderr, "Size of file should be 4096, but is %jd\n", s.st_size );
		return 1;
	}
	
	/* Second one should fail with EEXIST */
	fd = open( "./mnt/testopen", O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR );
	if( fd < 0 && errno == EEXIST ) {
		// OK
	} else {
		fprintf( stderr, "Second create succedded and should not" );
		return 1;
	}
	
	/* Third one should success and append to the file */
	fd = open( "./mnt/testopen", O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR );
	
	/* check if the file has size 4096 */
	res = stat( "./mnt/testopen", &s );
	if( res < 0 ) {
		perror( "Error stating testopen" );
		return 1;
	}
	if( s.st_size == 4096 ) {
		// OK
	} else {
		fprintf( stderr, "Size of file should be 4096, but is %jd\n", s.st_size );
		return 1;
	}

	/* write some more data, this data should be appended */
	wres = write( fd, buf, 4096 );
	if( wres != 4096 ) {
		perror( "Error writing" );
		(void)close( fd );
		return 1;
	}

	(void)close( fd );	
	
	/* check if the file has size 2 * 4096 now */
	res = stat( "./mnt/testopen", &s );
	if( res < 0 ) {
		perror( "Error stating testopen" );
		return 1;
	}
	if( s.st_size == 8192 ) {
		// OK
	} else {
		fprintf( stderr, "Size of file should be 8192, but is %jd\n", s.st_size );
		return 1;
	}
	
	/* Fourth one should success and truncate the file */
	fd = open( "./mnt/testopen", O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR );
	(void)close( fd );	
	
	/* check if the file has size zero */
	res = stat( "./mnt/testopen", &s );
	if( res < 0 ) {
		perror( "Error stating testopen" );
		return 1;
	}
	if( s.st_size == 0 ) {
		// OK
	} else {
		fprintf( stderr, "Size of file should be 0, but is %jd\n", s.st_size );
		return 1;
	}
	
	res = unlink( "./mnt/testopen" );
	if( res < 0 ) {
		perror( "Error removing testopen" );
		return 1;
	}
	
	return 0;
}
