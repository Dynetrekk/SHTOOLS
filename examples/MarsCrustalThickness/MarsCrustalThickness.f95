program MarsCrustalThickness
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!	This program will compute the relief along the crust-mantle interface that
!	is needed to explain the martian gravity field. This crustal thickness model 
!	is "anchored" by chosing a minimum crustal thickness.
!	
!	Note that in this program, that the maximum spherical harmonic degree that is used
!	when calculating the relief raised to the nth power is the input spherical harmonic 
!	degree. This is not entirely correct, as the relief raised to the nth power generates
!	a spherical harmonic field up to lmax*n. However, as it is also not correct to assume
!	that the topo and gravity field are bandlimited with a maximum spherical harmonic degree
!	of lmax, this approximation is probably ok.
!
!	Written by Mark Wieczorek 2003
!
!	Copyright (c) 2005, Mark A. Wieczorek
!	All rights reserved.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

	use SHTOOLS

	implicit none
	integer, parameter :: max1 = 200
	real*8 :: 	r0, mass, rho_u, rho_l, pi, topo_c(2, max1+1, max1+1), &
			topogrid(max1+1, 2*max1+1), mohogrid(max1+1, 2*max1+1), &
			moho_c(2,max1+1, max1+1), bc(2,max1+1, max1+1), gm, &
			ba(2,max1+1, max1+1), pot(2,max1+1, max1+1), d, thick_min, &
			mohogrid_old(max1+1, 2*max1+1), delta, delta_max, &
			thick_delta, param(8), grav, cilm(2,max1+1, max1+1), &
			tmin, r_grav, zero(max1+1), w(max1+1), interval, &
			rref, misfit(2,max1+1, max1+1), &
			timein, timeout
	integer ::	l, m, lmax, i, nmax, nlat, nlong, &
			iter, j, r1, lmaxfile, filter_type, filter_degree
	character*80 ::	grav_file, moho_out, thick_grid_out, topo_file, misfit_file
	
	print*,  "rho_crust (kg/m3) > "
	read(*,*) rho_u
	print*, "rho_mantle (kg/m3) > "
	read(*,*) rho_l
	
	pi = acos(-1.0d0)
	delta_max = 1.0d0
	grav = 6.67407d-11		! gravitational constant of Schlamminger et al (2002)

	
	nmax = 5	! nmax of Wieczorek and Phillips (1998)
	
	print*, "Input filter type (1) Minimum amplitude, (2) minimum curvature, (0) no filter "
	read(*,*) filter_type
	if (filter_type /= 0 ) then
		print*, "Degree at which the filter is 1/2 " 
		read(*,*) filter_degree
	endif
		
	grav_file = "../ExampleDataFiles/jgm85h02.sh"
	topo_file = "../ExampleDataFiles/Mars2000.shape"
	
	print*, "Remove degree 1 topo coefficients from Bouguer Correction? (0:no, 1:yes) > "
	read(*,*) r1
	
	print*, "maximum degree to compute Moho relief to >"
	read(*,*) lmax
	
	nlat = NGLQSH(lmax)
	nlong = 2*lmax+1

	print*, "Minimum assumed crustal thickness (km) > "
	read(*,*) thick_min
	thick_min = thick_min*1.d3
		
	print*, "Moho spherical harmonic coeficient output filename > "
	read(*,*) moho_out
	print*, "Grid spacing for output crustal thickness map (degrees) > "
	read(*,*) interval
	print*, "gridded crustal thickness output filename >"
	read(*,*) thick_grid_out
	print*, "Gravity misfit spherical harmonic filename >"
	read(*,*) misfit_file
	
	call cpu_time(timein)
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!
	!	Read topo and grav files 
	!
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	print*, "Reading data from ", grav_file
	call SHRead(grav_file, pot, lmaxfile, header=param(1:2))
	
	gm = param(2)
	r_grav = param(1)
	mass = gm/grav
	
	print*, "Mass (kg) = ", mass
	print*, "Lmax of file = ", lmaxfile
	
	if (lmaxfile > lmax) then
		pot(:,lmax+2:lmaxfile+1,lmax+2:lmaxfile+1) = 0.0d0	
		! zero coefficients greater than lmax
	endif

	print*, "Reading data from ", topo_file
	call SHRead(topo_file, topo_c, lmaxfile, header=param(1:8))
	print*, "Lmax of file = ", lmaxfile
	
	if (lmaxfile > lmax) then
		topo_c(:,lmax+2:lmaxfile+1,lmax+2:lmaxfile+1) = 0.0d0	
		! zero coefficients greater than lmax
	endif
		
	r0 = topo_c(1,1,1)
	print*, "r0 (km) = ", r0/1.d3
		
	! Downward continue gravity coefficients from 3397 to MPR
	
	do l = 2, lmax
		pot(:,l+1,:) = pot(:,l+1,:) * (r_grav/r0)**l
	enddo
			
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!
	! 	Call a routine which will compute a number of arrays that will be used later on 
	!	(these include the guass points, weights, and plx).
	!
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	print*, "Precomputing data structures..."
	call PreCompute(lmax, zero, w)

	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!
	!	Create Bouger anomaly up to degree nmax
	!
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

	print*, "Creating Bouger anomaly"
	
	call MakeGridGLQ(topogrid, topo_c, lmax, zero=zero)
	
	print*, "Maximum Topo (km) = ", maxval(topogrid(1:nlat, 1:nlong))/1.d3
	print*, "Minimum Topo (km) = ", minval(topogrid(1:nlat, 1:nlong))/1.d3
	
	call CilmPlus(bc, topogrid, lmax, nmax, mass, rref, rho_u, gridtype = 1, w = w, zero=zero)
		
	ba = pot - bc	! This is the bouguer anomaly
	
	if (r1==1) ba(:,2,:) = 0.0d0  
		
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!
	!	Compute crustal thickness by iterating at each
	!	reference moho depth. Gravity anomalies are calculated
	!	using n*lmax coefficients, but only the first lmax are
	!	used in the crustal thickness calculations.
	!
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	thick_delta = 1.d9
	
	d = r0 -44.d3		! initial reference moho depth

	do while (abs(thick_delta) > delta_max)
	
		write(*,*)
		print*, "Reference depth (km) = ", (r0-d)/1.d3
		
		moho_c = 0.0d0
		moho_c(1,1,1) = d
		
		do l=1, lmax
			moho_c(:,l+1,1:l+1) =  ba(:,l+1,1:l+1) *mass * (2.0d0*l+1.0d0) * ((r0/d)**l) &
				/(4.0d0*pi*(rho_l-rho_u)*d**2)
		enddo
	
		call MakeGridGLQ(mohogrid_old, moho_c, lmax, zero=zero)
	
		print*, "Maximum Crustal thickness (km) = ", maxval(topogrid(1:nlat, 1:nlong)-mohogrid_old(1:nlat, 1:nlong))/1.d3
		print*, "Minimum Crustal thickness (km) = ", minval(topogrid(1:nlat, 1:nlong)-mohogrid_old(1:nlat, 1:nlong))/1.d3
	
		iter = 0
		delta = 1.d9
	
		do while(delta > delta_max)
		
			iter = iter +1	
			print*, "Iteration ", iter
	
			call Hilm(moho_c, ba, mohogrid_old, lmax, nmax, mass, r0, rho_l-rho_u, w, &
				zero = zero, filter_type=filter_type, filter_deg=filter_degree)
		
			call MakeGridGLQ(mohogrid, moho_c, lmax, zero=zero)
		
			delta = maxval(abs(mohogrid(1:nlat, 1:nlong)-mohogrid_old(1:nlat, 1:nlong)))
		
			print*, "Delta (km) = ", delta/1.d3
			print*, "Maximum Crustal thickness (km) = ", maxval(topogrid(1:nlat, 1:nlong)-mohogrid(1:nlat, 1:nlong))/1.d3
			print*, "Minimum Crustal thickness (km) = ", minval(topogrid(1:nlat, 1:nlong)-mohogrid(1:nlat, 1:nlong))/1.d3
		
			tmin = minval(topogrid(1:nlat, 1:nlong)-mohogrid(1:nlat, 1:nlong))
			mohogrid_old = mohogrid
	
		enddo
	
		call CilmPlus(cilm, mohogrid, lmax, nmax, mass, rref, rho_l-rho_u, gridtype = 1, w = w, zero=zero)
	
		d = d + 1.0*(tmin-thick_min)
		thick_delta  = tmin  - thick_min
	
	enddo
	
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	!
	!	Determine misfit between observed and calculated gravity, and write
	!	data to external files. Note that here, only coefficients up to lmax
	!	are considered.
	!
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	! upward continue moho coefficients
	do l=0, lmax
		cilm(:,l+1,1:l+1) = cilm(:,l+1,1:l+1) * (d/r0)**l
	enddo
	
	misfit = pot - (bc+ cilm) 	! this is the misfit
	misfit(1,1,1) = 0.0d0		! ignore degree-0 misfit
	
	do l=0, lmax
		cilm(:,l+1,1:l+1) = misfit(:,l+1,1:l+1)*(l+1.0d0)*gm*(1.0d5)/r0**2	
	enddo
	
	call MakeGridGLQ(mohogrid_old, cilm, lmax, zero=zero)
	
	print*, "Maximum misfit (mgals) = ", maxval(mohogrid_old(1:nlat, 1:nlong))
	print*, "Minimum misfit (mgals) = ", minval(mohogrid_old(1:nlat, 1:nlong))

	print*, "Mean Crustal Thickness (km) =", (r0-moho_c(1,1,1))/1.d3
	
	print*, "Writing output data"
	
	open(12,file=moho_out)
	
	do l=0,lmax
		do m=0,l
			write(12,*) l, m, moho_c(1,l+1,m+1), moho_c(2,l+1,m+1)
		enddo
	enddo
	
	close(12)
	
	call MakeGrid2d(topogrid, topo_c - moho_c, lmax, interval, nlat, nlong)
	
	open(12, file=thick_grid_out)
	write(12,*) nlat, nlong
	do i=1, nlat
		do j=1,nlong
			write(12,*) topogrid(i,j)/1.d3
		enddo
	enddo
	
	close(12)
	
	open(12, file=misfit_file)
	do l=0,lmax
		do m=0,l
			write(12,*) l, m, misfit(1,l+1,m+1), misfit(2,l+1,m+1)
		enddo
	enddo
	
	close(12)
	
	call cpu_time(timeout)
	print*, "time (sec) = ", timeout-timein

end program MarsCrustalThickness

