! routines doing 3D, 2D and 1D interpolation

subroutine interp_2d_field_v2(num_lon_reg, num_lat_reg, lon_reg, lat_reg, data_reg, missvalue, &
     num_mod, lon_mod, lat_mod, data_mod)
  !-------------------------------------------------------------------------------------
  ! A second version of 2D interpolation.
  ! This routine does 2d interpolation from a regular grid to specified nodes
  ! on the surface grid. The regular grid is assumed to be global. 
  ! In this version the missing value will be checked. If a model grid point is outside
  ! the ocean, the nearest value will be assigned.
  ! The output is data_mod, others are input.
  ! Arguments:
  ! num_lon_reg				number of regular grid points in the longitude direction
  ! num_lat_reg				number of regular grid points in the latitude direction
  ! lon_reg(num_lon_reg)		longitude of the regular grid points
  ! lat_reg(num_lat_reg)        	latitude of the regular grid points
  ! data_reg(num_lon_reg, num_lat_reg) 	data on the regular grid
  ! missvalue                           missing value in the raw data
  ! num_mod      			number of interpolation nodes
  ! lon_mod(num_mod)			longitude of interpolation nodes
  ! lat_mod(num_mod)			latitude of interpolation nodes
  ! data_mod(num_mod)			output data on interpolation nodes
  ! Unit of lon_reg, lat_reg, lon_mod, lat_mod: degree
  ! Order of lon_reg: monotonically increasing in the range [0 360]  
  !                   (range [180,360] is associated with longitude [-180, 0])
  ! Order of lat_reg: monotonically increasing in the range [-90 90]
  ! Make sure that 'lon_mod' is also in the [0, 360] range.
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !-------------------------------------------------------------------------------------
  
  implicit none
  integer             		:: n, i, ii, jj, k, nod_find
  integer			:: ind_lat_h, ind_lat_l, ind_lon_h, ind_lon_l
  integer, intent(in)         	:: num_lon_reg, num_lat_reg, num_mod
  real(kind=8) 			:: x, y, diff, d, dmin
  real(kind=8)			:: rt_lat1, rt_lat2, rt_lon1, rt_lon2
  real(kind=8)                  :: data(2,2)
  real(kind=8)                  :: data_lo, data_up
  real(kind=8), intent(in)	:: lon_reg(num_lon_reg), lat_reg(num_lat_reg)
  real(kind=8), intent(in)	:: data_reg(num_lon_reg, num_lat_reg), missvalue
  real(kind=8), intent(in)	:: lon_mod(num_mod), lat_mod(num_mod)
  real(kind=8), intent(out)  	:: data_mod(num_mod)
  !
  if(lon_reg(1)<0.0 .or. lon_reg(num_lon_reg)>360.) then
     write(*,*) 'Error in 2D interpolation!'
     write(*,*) 'The regular grid is not in the proper longitude range.'
     call par_ex
     stop
  end if

  do n=1,num_mod
     x=lon_mod(n)
     y=lat_mod(n)
     ! find the surrounding rectangular box and get interpolation ratios
     ! 1) north-south direction
     if(y<lat_reg(1)) then
        ind_lat_h=2
        ind_lat_l=1
        y=lat_reg(1)
     elseif(y>lat_reg(num_lat_reg)) then
        ind_lat_h=num_lat_reg
        ind_lat_l=num_lat_reg-1
        y=lat_reg(num_lat_reg)
     else
        do i=2,num_lat_reg
           if(lat_reg(i)>=y) then
              ind_lat_h=i
              ind_lat_l=i-1
              exit
           end if
        end do
     end if
     diff=lat_reg(ind_lat_h)-lat_reg(ind_lat_l)
     rt_lat1=(lat_reg(ind_lat_h)-y)/diff
     rt_lat2=1.0-rt_lat1
     ! 2) east_west direction
     if(x<lon_reg(1)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     elseif(x>lon_reg(num_lon_reg)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon2=(x-lon_reg(ind_lon_l))/diff
        rt_lon1=1.0-rt_lon2
     else
        do i=2,num_lon_reg
           if(lon_reg(i)>=x) then
              ind_lon_h=i
              ind_lon_l=i-1
              exit
           end if
        end do
        diff=lon_reg(ind_lon_h)-lon_reg(ind_lon_l)
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     end if
     !
     data(1,1)=data_reg(ind_lon_l,ind_lat_l)
     data(1,2)=data_reg(ind_lon_l,ind_lat_h)
     data(2,1)=data_reg(ind_lon_h,ind_lat_l)
     data(2,2)=data_reg(ind_lon_h,ind_lat_h)
     !
     ! interpolate data
     if(any(data==missvalue)) then
        dmin=10000.0
        nod_find=0
        do k=1,5
           do ii=max(1,ind_lon_l-k+1),min(num_lon_reg,ind_lon_l+k)
              do jj=max(1,ind_lat_l-k+1),min(num_lat_reg,ind_lat_l+k)
                 if(data_reg(ii,jj)==missvalue) cycle
                 d=(x-lon_reg(ii))**2 + (y-lat_reg(jj))**2
                 if(d<dmin) then
                    nod_find=1
                    data_mod(n)=data_reg(ii,jj)
                    dmin=d
                 end if
              end do
           end do
           if(nod_find==1) exit
        end do
     else
        data_mod(n)=(data(1,1)*rt_lon1 + data(2,1)*rt_lon2)*rt_lat1 + &
             (data(1,2)*rt_lon1 + data(2,2)*rt_lon2)*rt_lat2
     end if
  end do
end subroutine interp_2d_field_v2
!
!---------------------------------------------------------------------------
!
subroutine interp_2d_field(num_lon_reg, num_lat_reg, lon_reg, lat_reg, data_reg, &
     num_mod, lon_mod, lat_mod, data_mod, phase_flag)
  !-------------------------------------------------------------------------------------
  ! This routine does 2d interpolation from a regular grid to specified nodes
  ! on the surface grid. The regular grid is assumed to be global.
  ! This version assumes that no dummy values exist in the raw data.
  ! The argument 'phase_flag' is used to set if a phase angle field is to be interpolated.
  ! The output is data_mod, others are input.
  ! Arguments:
  ! num_lon_reg				number of regular grid points in the longitude direction
  ! num_lat_reg				number of regular grid points in the latitude direction
  ! lon_reg(num_lon_reg)		longitude of the regular grid points
  ! lat_reg(num_lat_reg)        	latitude of the regular grid points
  ! data_reg(num_lon_reg, num_lat_reg) 	data on the regular grid
  ! num_mod      			number of interpolation nodes
  ! lon_mod(num_mod)			longitude of interpolation nodes
  ! lat_mod(num_mod)			latitude of interpolation nodes
  ! data_mod(num_mod)			output data on interpolation nodes
  ! phase_flag                          1: interpolate phase angle (0-360�); 0: otherwise
  ! Unit of lon_reg, lat_reg, lon_mod, lat_mod: degree
  ! Order of lon_reg: monotonically increasing in the range [0 360]  
  !                   (range [180,360] is associated with longitude [-180, 0])
  ! Order of lat_reg: monotonically increasing in the range [-90 90]
  ! Make sure that 'lon_mod' is also in the [0, 360] range.
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !-------------------------------------------------------------------------------------
  implicit none
  integer             		:: n, i
  integer			:: ind_lat_h, ind_lat_l, ind_lon_h, ind_lon_l
  integer, intent(in)         	:: num_lon_reg, num_lat_reg, num_mod
  integer, intent(in)          	:: phase_flag
  real(kind=8) 			:: x, y, diff
  real(kind=8)			:: rt_lat1, rt_lat2, rt_lon1, rt_lon2
  real(kind=8)                  :: data_ll, data_lh, data_hl, data_hh
  real(kind=8)                  :: data_lo, data_up
  real(kind=8), intent(in)	:: lon_reg(num_lon_reg), lat_reg(num_lat_reg)
  real(kind=8), intent(in)	:: data_reg(num_lon_reg, num_lat_reg)
  real(kind=8), intent(in)	:: lon_mod(num_mod), lat_mod(num_mod)
  real(kind=8), intent(out)  	:: data_mod(num_mod)
  !
  if(lon_reg(1)<0.0 .or. lon_reg(num_lon_reg)>360.) then
     write(*,*) 'Error in 2D interpolation!'
     write(*,*) 'The regular grid is not in the proper longitude range.'
     call par_ex
     stop
  end if

  do n=1,num_mod
     x=lon_mod(n)
     y=lat_mod(n)
     ! find the surrounding rectangular box and get interpolation ratios
     ! 1) north-south direction
     if(y<lat_reg(1)) then
        ind_lat_h=2
        ind_lat_l=1
        y=lat_reg(1)
     elseif(y>lat_reg(num_lat_reg)) then
        ind_lat_h=num_lat_reg
        ind_lat_l=num_lat_reg-1
        y=lat_reg(num_lat_reg)
     else
        do i=2,num_lat_reg
           if(lat_reg(i)>=y) then
              ind_lat_h=i
              ind_lat_l=i-1
              exit
           end if
        end do
     end if
     diff=lat_reg(ind_lat_h)-lat_reg(ind_lat_l)
     rt_lat1=(lat_reg(ind_lat_h)-y)/diff
     rt_lat2=1.0-rt_lat1
     ! 2) east_west direction
     if(x<lon_reg(1)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     elseif(x>lon_reg(num_lon_reg)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon2=(x-lon_reg(ind_lon_l))/diff
        rt_lon1=1.0-rt_lon2
     else
        do i=2,num_lon_reg
           if(lon_reg(i)>=x) then
              ind_lon_h=i
              ind_lon_l=i-1
              exit
           end if
        end do
        diff=lon_reg(ind_lon_h)-lon_reg(ind_lon_l)
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     end if
     !
     data_ll=data_reg(ind_lon_l,ind_lat_l)
     data_lh=data_reg(ind_lon_l,ind_lat_h)
     data_hl=data_reg(ind_lon_h,ind_lat_l)
     data_hh=data_reg(ind_lon_h,ind_lat_h)
     !
     ! interpolate data
     if(phase_flag==1) then   ! interpolate phase value (0,360)
        if(abs(data_ll-data_hl)>180.) then
           if(data_ll<data_hl) then
              data_ll=data_ll+360.
           else
              data_hl=data_hl+360.
           end if
        end if
        if(abs(data_lh-data_hh)>180.) then
           if(data_lh<data_hh) then
              data_lh=data_lh+360.
           else
              data_hh=data_hh+360.
           end if
        end if
        data_lo = data_ll*rt_lon1 + data_hl*rt_lon2                
        data_up = data_lh*rt_lon1 + data_hh*rt_lon2
        if(abs(data_lo-data_up)>180.) then
           if(data_lo<data_up) then
              data_lo=data_lo+360.
           else
              data_up=data_up+360.
           end if
        end if
        data_mod(n)=data_lo*rt_lat1 + data_up*rt_lat2
        if(data_mod(n)>=360.) then
           data_mod(n)=mod(data_mod(n), 360.)
        end if
     else   ! other case
        data_mod(n)=(data_ll*rt_lon1 + data_hl*rt_lon2)*rt_lat1 + &
             (data_lh*rt_lon1 + data_hh*rt_lon2)*rt_lat2
     end if
  end do
end subroutine interp_2d_field
!
!---------------------------------------------------------------------------
!
subroutine interp_3d_field(num_lon_reg, num_lat_reg, num_lay_reg, &
     lon_reg, lat_reg, lay_reg, data_reg, &
     num_mod, lon_mod, lat_mod, lay_mod, data_mod)
  !-------------------------------------------------------------------------------------
  ! This routine does 3d interpolation from a regular grid to specified nodes.
  ! The regular grid is assumed to be global.
  ! The output is data_mod, others are input.
  ! Arguments:
  ! num_lon_reg				number of regular grid points in the longitude direction
  ! num_lat_reg				number of regular grid points in the latitude direction
  ! num_lay_reg				number of regular grid points in the vertical direction
  ! lon_reg(num_lon_reg)		longitude of the regular grid points
  ! lat_reg(num_lat_reg)        	latitude of the regular grid points
  ! lay_reg(num_lay_reg)                depth of the regular grid points
  ! data_reg(:,:,:)  	                data on the regular grid
  ! num_mod      			number of interpolation nodes
  ! lon_mod(num_mod)			longitude of interpolation nodes
  ! lat_mod(num_mod)			latitude of interpolation nodes
  ! lay_mod(num_mod)                    depth of interpolation nodes
  ! data_mod(num_mod)			output data on interpolation nodes
  ! Unit of lon_reg, lat_reg, lon_mod, lat_mod: degree
  ! Unit of lay_reg, lay_mod: m
  ! Order of lon_reg: monotonically increasing in the range [0 360]  
  !                   (range [180,360] is associated with longitude [-180, 0])
  ! Order of lat_reg: monotonically increasing in the range [-90 90]
  ! Order of lay_reg: monotonically decreasing from surface to bottom
  ! Make sure that 'lon_mod' is also in the [0, 360] range.
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !-------------------------------------------------------------------------------------
  
  implicit none
  integer             		:: n, i, flag
  integer			:: ind_lat_h, ind_lat_l, ind_lon_h, ind_lon_l
  integer                       :: ind_lay_h, ind_lay_l
  integer, intent(in)         	:: num_lon_reg, num_lat_reg, num_lay_reg
  integer, intent(in)          	:: num_mod
  real(kind=8) 			:: x, y, z, diff 
  real(kind=8)			:: rt_lat1, rt_lat2, rt_lon1, rt_lon2
  real(kind=8)                  :: rt_lay1, rt_lay2, v_dup, v_dlo
  real(kind=8)                  :: data_ll, data_lh, data_hl, data_hh
  real(kind=8)                  :: v_col(4), z_col(4), H, aux1, aux2
  real(kind=8)                  :: dz, a, b, c, d
  real(kind=8), intent(in)	:: lon_reg(num_lon_reg), lat_reg(num_lat_reg)
  real(kind=8), intent(in)      :: lay_reg(num_lay_reg)
  real(kind=8), intent(in)	:: data_reg(num_lon_reg, num_lat_reg, num_lay_reg)
  real(kind=8), intent(in)	:: lon_mod(num_mod), lat_mod(num_mod), lay_mod(num_mod)
  real(kind=8), intent(out)  	:: data_mod(num_mod)

  do n=1,num_mod
     x=lon_mod(n)
     y=lat_mod(n)
     z=lay_mod(n)

     ! find the surrounding box and get interpolation ratios

     ! 1) north-south direction
     if(y<lat_reg(1)) then
        ind_lat_h=2
        ind_lat_l=1
        y=lat_reg(1)
     elseif(y>lat_reg(num_lat_reg)) then
        ind_lat_h=num_lat_reg
        ind_lat_l=num_lat_reg-1
        y=lat_reg(num_lat_reg)
     else
        do i=2,num_lat_reg
           if(lat_reg(i)>=y) then
              ind_lat_h=i
              ind_lat_l=i-1
              exit
           end if
        end do
     end if
     diff=lat_reg(ind_lat_h)-lat_reg(ind_lat_l)
     rt_lat1=(lat_reg(ind_lat_h)-y)/diff
     rt_lat2=1.0-rt_lat1

     ! 2) east_west direction
     if(x<lon_reg(1)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     elseif(x>lon_reg(num_lon_reg)) then
        ind_lon_h=1
        ind_lon_l=num_lon_reg
        diff=lon_reg(ind_lon_h)+(360.-lon_reg(ind_lon_l))
        rt_lon2=(x-lon_reg(ind_lon_l))/diff
        rt_lon1=1.0-rt_lon2
     else
        do i=2,num_lon_reg
           if(lon_reg(i)>=x) then
              ind_lon_h=i
              ind_lon_l=i-1
              exit
           end if
        end do
        diff=lon_reg(ind_lon_h)-lon_reg(ind_lon_l)
        rt_lon1=(lon_reg(ind_lon_h)-x)/diff
        rt_lon2=1.0-rt_lon1
     end if

     ! 3) up-down direction
     if(z>lay_reg(1)) then
        ind_lay_h=1
        ind_lay_l=2
        z=lay_reg(1)
     elseif(z<lay_reg(num_lay_reg)) then
        ind_lay_h=num_lay_reg-1
        ind_lay_l=num_lay_reg
        z=lay_reg(num_lay_reg)
     else
        do i=2,num_lay_reg
           if(lay_reg(i)<=z) then
              ind_lay_h=i-1
              ind_lay_l=i
              exit
           end if
        end do
     end if
     diff=lay_reg(ind_lay_h)-lay_reg(ind_lay_l)
     rt_lay1=(z-lay_reg(ind_lay_l))/diff
     rt_lay2=1.0-rt_lay1

     data_ll=data_reg(ind_lon_l,ind_lat_l,ind_lay_h)
     data_lh=data_reg(ind_lon_l,ind_lat_h,ind_lay_h)
     data_hl=data_reg(ind_lon_h,ind_lat_l,ind_lay_h)
     data_hh=data_reg(ind_lon_h,ind_lat_h,ind_lay_h)    
     v_dup=(data_ll*rt_lon1 + data_hl*rt_lon2)*rt_lat1 + &
          (data_lh*rt_lon1 + data_hh*rt_lon2)*rt_lat2

     data_ll=data_reg(ind_lon_l,ind_lat_l,ind_lay_l)
     data_lh=data_reg(ind_lon_l,ind_lat_h,ind_lay_l)
     data_hl=data_reg(ind_lon_h,ind_lat_l,ind_lay_l)
     data_hh=data_reg(ind_lon_h,ind_lat_h,ind_lay_l)    
     v_dlo=(data_ll*rt_lon1 + data_hl*rt_lon2)*rt_lat1 + &
          (data_lh*rt_lon1 + data_hh*rt_lon2)*rt_lat2

     data_mod(n)=v_dup*rt_lay1 + v_dlo*rt_lay2

  end do
end subroutine interp_3d_field
!
!---------------------------------------------------------------------------
!
subroutine interp_vertical_section(num_hor_reg, num_ver_reg, hor_reg, ver_reg, data_reg, &
	num_mod, hor_mod, ver_mod, data_mod)
  !-------------------------------------------------------------------------------------
  ! This routine does 2d interpolation from a regular grid to specified nodes
  ! in a vertical section.
  ! The output is data_mod, others are input.
  ! Arguments:
  ! num_hor_reg				number of regular grid points in the horizontal direction
  ! num_ver_reg				number of regular grid points in the vertical direction
  ! hor_reg(num_hor_reg)		horizontal coord. of the regular grid points
  ! ver_reg(num_ver_reg)        	vertical coord. of the regular grid points
  ! data_reg(num_hor_reg, num_ver_reg) 	data on the regular grid
  ! num_mod      			number of interpolation nodes
  ! hor_mod(num_mod)			horizontal coord. of interpolation nodes
  ! ver_mod(num_mod)			vertical coord. of interpolation nodes
  ! data_mod(num_mod)			output data on interpolation nodes
  ! Unit of hor_reg and hor_mod should be the same (in lon or lat unit)
  ! Unit of ver_reg and ver_mod should be the same (usually in m)
  ! Order of hor_reg: monotonically increasing
  ! Order of ver_reg: monotonically decreasing (from ocean top to bottom)
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !-------------------------------------------------------------------------------------
  
  implicit none
  integer             		:: n, i
  integer			:: ind_ver_h, ind_ver_l, ind_hor_h, ind_hor_l
  integer, intent(in)         	:: num_ver_reg, num_hor_reg, num_mod
  real(kind=8) 			:: x, z, diff
  real(kind=8)			:: rt_ver1, rt_ver2, rt_hor1, rt_hor2
  real(kind=8)                  :: data_ll, data_lh, data_hl, data_hh
  real(kind=8), intent(in)	:: ver_reg(num_ver_reg), hor_reg(num_hor_reg)
  real(kind=8), intent(in)	:: data_reg(num_hor_reg, num_ver_reg)
  real(kind=8), intent(in)	:: ver_mod(num_mod), hor_mod(num_mod)
  real(kind=8), intent(out)  	:: data_mod(num_mod)
  !
  do n=1,num_mod
        x=hor_mod(n)
        z=ver_mod(n)
        ! find the surrounding rectangular box and get interpolation ratios
        ! 1) vertical direction
        if(z>ver_reg(1)) then
           ind_ver_h=2
           ind_ver_l=1
           z=ver_reg(1)
        elseif(z<ver_reg(num_ver_reg)) then
           ind_ver_h=num_ver_reg
           ind_ver_l=num_ver_reg-1
           z=ver_reg(num_ver_reg)
        else
           do i=2,num_ver_reg
              if(ver_reg(i)<=z) then
                 ind_ver_h=i
                 ind_ver_l=i-1
                 exit
              end if
           end do
        end if
        diff=ver_reg(ind_ver_h)-ver_reg(ind_ver_l)
        rt_ver1=(ver_reg(ind_ver_h)-z)/diff
        rt_ver2=1.0-rt_ver1
        ! 2) east_west or north_south direction
        if(x<hor_reg(1)) then
           ind_hor_h=2
           ind_hor_l=1
	   x=hor_reg(1)
        elseif(x>hor_reg(num_hor_reg)) then
           ind_hor_h=num_hor_reg
           ind_hor_l=num_hor_reg-1
	   x=hor_reg(num_hor_reg)
        else
           do i=2,num_hor_reg
              if(hor_reg(i)>=x) then
                 ind_hor_h=i
                 ind_hor_l=i-1
                 exit
              end if
           end do
        end if
        diff=hor_reg(ind_hor_h)-hor_reg(ind_hor_l)
        rt_hor1=(hor_reg(ind_hor_h)-x)/diff
        rt_hor2=1.0-rt_hor1  
        !
        data_ll=data_reg(ind_hor_l,ind_ver_l)
        data_lh=data_reg(ind_hor_l,ind_ver_h)
        data_hl=data_reg(ind_hor_h,ind_ver_l)
        data_hh=data_reg(ind_hor_h,ind_ver_h)
        !
        ! interpolate data
        data_mod(n)=(data_ll*rt_hor1 + data_hl*rt_hor2)*rt_ver1 + &
           (data_lh*rt_hor1 + data_hh*rt_hor2)*rt_ver2     
  end do 

end subroutine interp_vertical_section
!
!---------------------------------------------------------------------------
!
subroutine interp_1d(num_reg, x_reg, data_reg, num_mod, x_mod, data_mod)
  ! not tested yet
  !-------------------------------------------------------------------------------------
  ! This routine does 1d interpolation from a regular grid to specified nodes
  ! The output is data_mod, others are input.
  ! Arguments:
  ! num_reg			number of regular grid points
  ! x_reg(num_hor_reg)	        coord. of the regular grid points
  ! data_reg(num_regg) 	        data on the regular grid
  ! num_mod      		number of interpolation nodes
  ! x_mod(num_mod)		coord. of interpolation nodes
  ! data_mod(num_mod)		output data on interpolation nodes
  ! Unit of x_reg and x_mod should be the same (in lon or lat unit)
  ! Order of x_reg: monotonically increasing
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !-------------------------------------------------------------------------------------
  
  implicit none
  integer             		:: n, i
  integer			:: ind_h, ind_l
  integer, intent(in)         	:: num_reg, num_mod
  real(kind=8) 			:: x, diff
  real(kind=8)			:: rt_1, rt_2
  real(kind=8), intent(in)	:: x_reg(num_reg)
  real(kind=8), intent(in)	:: data_reg(num_reg)
  real(kind=8), intent(in)	:: x_mod(num_mod)
  real(kind=8), intent(out)  	:: data_mod(num_mod)
  !
  do n=1,num_mod
     x=x_mod(n)
     ! find the two surrounding grid points and get interpolation ratios
     if(x<x_reg(1)) then
        ind_h=2
        ind_l=1
        x=x_reg(1)
     elseif(x>x_reg(num_reg)) then
        ind_h=num_reg
        ind_l=num_reg-1
        x=x_reg(num_reg)
     else
        do i=2,num_reg
           if(x_reg(i)>=x) then
              ind_h=i
              ind_l=i-1
              exit
           end if
        end do
     end if
     diff=x_reg(ind_h)-x_reg(ind_l)
     rt_1=(x_reg(ind_h)-x)/diff
     rt_2=1.0-rt_1  
     !
     ! interpolate data
     data_mod(n)=data_reg(ind_l)*rt_1 + data_reg(ind_h)*rt_2
  end do

end subroutine interp_1d
!
!---------------------------------------------------------------------------




