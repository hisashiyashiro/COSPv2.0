! %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! Copyright (c) 2015, Regents of the University of Colorado
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without modification, are 
! permitted provided that the following conditions are met:
!
! 1. Redistributions of source code must retain the above copyright notice, this list of 
!    conditions and the following disclaimer.
!
! 2. Redistributions in binary form must reproduce the above copyright notice, this list
!    of conditions and the following disclaimer in the documentation and/or other 
!    materials provided with the distribution.
!
! 3. Neither the name of the copyright holder nor the names of its contributors may be 
!    used to endorse or promote products derived from this software without specific prior
!    written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
! EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
! MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
! THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
! SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT 
! OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
! INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
! LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
! OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
!
! History:
! 05/01/15  Dustin Swales - Original version
! 
! %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
module cosp_optics
  USE COSP_KINDS, ONLY: wp,dp
  USE COSP_MATH_CONSTANTS,  ONLY: pi
  USE COSP_PHYS_CONSTANTS,  ONLY: rholiq,km,rd,grav
  implicit none
  
  real(wp),parameter ::        & !
       ice_density   = 0.93_wp,& ! Ice density used in MODIS phase partitioning
       re_water_min  = 4._wp,  & ! Minimum effective radius (liquid)
       re_water_max  = 30._wp, & ! Maximum effective radius (liquid)
       re_ice_min    = 5._wp,  & ! Minimum effective radius (ice)
       re_ice_max    = 90._wp    ! Minimum effective radius (ice)
  integer, parameter ::        & !
       num_trial_res = 15,     & ! Increase to make the linear pseudo-retrieval of size 
       phaseIsLiquid = 1,      & !
       phaseIsIce    = 2         !
  ! Precompute near-IR optical params vs size for retrieval scheme
  integer, private :: i 
  real(wp), dimension(num_trial_res), parameter :: & 
       trial_re_w = re_water_min + (re_water_max - re_water_min)/ &
       (num_trial_res-1) * (/ (i - 1, i = 1, num_trial_res) /),   &
       trial_re_i = re_ice_min   + (re_ice_max -   re_ice_min)/   &
       (num_trial_res-1) * (/ (i - 1, i = 1, num_trial_res) /)
  
  interface cosp_simulator_optics
     module procedure cosp_simulator_optics2D, cosp_simulator_optics3D
  end interface cosp_simulator_optics
  
contains
  ! ##########################################################################
  !                          COSP_SIMULATOR_OPTICS
  !
  ! Used by: ISCCP, MISR and MODIS simulators
  ! ##########################################################################
  subroutine cosp_simulator_optics2D(dim1,dim2,dim3,flag,varIN1,varIN2,varOUT)
    ! INPUTS
    integer,intent(in) :: &
         dim1,   & ! Dimension 1 extent (Horizontal)
         dim2,   & ! Dimension 2 extent (Subcolumn)
         dim3      ! Dimension 3 extent (Vertical)
    real(wp),intent(in),dimension(dim1,dim2,dim3) :: &
         flag      ! Logical to determine the of merge var1IN and var2IN
    real(wp),intent(in),dimension(dim1,     dim3) :: &
         varIN1, & ! Input field 1
         varIN2    ! Input field 2
    ! OUTPUTS
    real(wp),intent(out),dimension(dim1,dim2,dim3) :: &
         varOUT    ! Merged output field
    ! LOCAL VARIABLES
    integer :: j
    
    varOUT(1:dim1,1:dim2,1:dim3) = 0._wp
    do j=1,dim2
       where(flag(:,j,:) .eq. 1)
          varOUT(:,j,:) = varIN2
       endwhere
       where(flag(:,j,:) .eq. 2)
          varOUT(:,j,:) = varIN1
       endwhere
    enddo
  end subroutine cosp_simulator_optics2D
  subroutine cosp_simulator_optics3D(dim1,dim2,dim3,flag,varIN1,varIN2,varOUT)
    ! INPUTS
    integer,intent(in) :: &
         dim1,   & ! Dimension 1 extent (Horizontal)
         dim2,   & ! Dimension 2 extent (Subcolumn)
         dim3      ! Dimension 3 extent (Vertical)
    real(wp),intent(in),dimension(dim1,dim2,dim3) :: &
         flag      ! Logical to determine the of merge var1IN and var2IN
    real(wp),intent(in),dimension(dim1,dim2,dim3) :: &
         varIN1, & ! Input field 1
         varIN2    ! Input field 2
    ! OUTPUTS
    real(wp),intent(out),dimension(dim1,dim2,dim3) :: &
         varOUT    ! Merged output field
    ! LOCAL VARIABLES
    integer :: j
    
    varOUT(1:dim1,1:dim2,1:dim3) = 0._wp
   where(flag(:,:,:) .eq. 1)
       varOUT(:,:,:) = varIN2
    endwhere
    where(flag(:,:,:) .eq. 2)
       varOUT(:,:,:) = varIN1
    endwhere
    
  end subroutine cosp_simulator_optics3D
  
  ! ##############################################################################
  !                           MODIS_OPTICS_PARTITION
  !
  ! For the MODIS simulator, there are times when only a sinlge optical depth
  ! profile, cloud-ice and cloud-water are provided. In this case, the optical
  ! depth is partitioned by phase.
  ! ##############################################################################
  subroutine MODIS_OPTICS_PARTITION(npoints,nlev,ncolumns,cloudWater,cloudIce,waterSize, &
                                    iceSize,tau,tauL,tauI)
    ! INPUTS
    INTEGER,intent(in) :: &
         npoints,   & ! Number of horizontal gridpoints
         nlev,      & ! Number of levels
         ncolumns     ! Number of subcolumns
    REAL(wp),intent(in),dimension(npoints,nlev,ncolumns) :: &
         cloudWater, & ! Subcolumn cloud water content
         cloudIce,   & ! Subcolumn cloud ice content
         waterSize,  & ! Subcolumn cloud water effective radius
         iceSize,    & ! Subcolumn cloud ice effective radius
         tau           ! Optical thickness
    
    ! OUTPUTS
    real(wp),intent(out),dimension(npoints,nlev,ncolumns) :: &
         tauL,       & ! Partitioned liquid optical thickness.
         tauI          ! Partitioned ice optical thickness.
    ! LOCAL VARIABLES
    real(wp),dimension(nlev,ncolumns) :: fracL
    integer                           :: i
    
    
    do i=1,npoints
       where(cloudIce(i,:, :) <= 0.) 
          fracL(:, :) = 1._wp
       elsewhere
          where (cloudWater(i,:, :) <= 0.) 
             fracL(:, :) = 0._wp
          elsewhere 
             ! Geometic optics limit - tau as LWP/re  (proportional to LWC/re) 
             fracL(:, :) = (cloudWater(i,:, :)/waterSize(i,:, :)) / &
                  (cloudWater(i,:, :)/waterSize(i,:, :) + cloudIce(i,:, :)/(ice_density * iceSize(i,:, :)) ) 
          end where
       end where
       tauL(i,:, :) = fracL(:, :) * tau(i,:, :) 
       tauI(i,:, :) = tau(i,:, :) - tauL(i,:, :)
    enddo
    
  end subroutine MODIS_OPTICS_PARTITION
  ! ########################################################################################
  !                                   MODIS_OPTICS
  ! 
  ! ########################################################################################
  subroutine modis_optics(nPoints,nLevels,nSubCols,num_trial_res,tauLIQ,sizeLIQ,tauICE,sizeICE,&
                          fracLIQ, g, w0)
    ! INPUTS
    integer, intent(in)                                      :: nPoints,nLevels,nSubCols,num_trial_res
    real(wp),intent(in),dimension(nPoints,nSubCols,nLevels)  :: tauLIQ, sizeLIQ, tauICE, sizeICE
    ! OUTPUTS
    real(wp),intent(out),dimension(nPoints,nSubCols,nLevels) :: g,w0,fracLIQ
    ! LOCAL VARIABLES
    real(wp), dimension(nLevels)            :: water_g, water_w0, ice_g, ice_w0,tau
    integer :: i,j
    
    ! Initialize
    g(1:nPoints,1:nSubCols,1:nLevels)  = 0._wp
    w0(1:nPoints,1:nSubCols,1:nLevels) = 0._wp
    
    do j =1,nPoints
       do i=1,nSubCols
          water_g(1:nLevels)  = get_g_nir(  phaseIsLiquid, sizeLIQ(j,i,1:nLevels)) 
          water_w0(1:nLevels) = get_ssa_nir(phaseIsLiquid, sizeLIQ(j,i,1:nLevels))
          ice_g(1:nLevels)    = get_g_nir(  phaseIsIce,    sizeICE(j,i,1:nLevels))
          ice_w0(1:nLevels)   = get_ssa_nir(phaseIsIce,    sizeICE(j,i,1:nLevels))
          
          ! Combine ice and water optical properties
          tau(1:nLevels) = tauICE(j,i,1:nLevels) + tauLIQ(j,i,1:nLevels) 
          where (tau(1:nLevels) > 0) 
             g(j,i,1:nLevels)  = (tauLIQ(j,i,1:nLevels)*water_g(1:nLevels) + tauICE(j,i,1:nLevels)*ice_g(1:nLevels)) / & 
                  tau(1:nLevels) 
             w0(j,i,1:nLevels) = (tauLIQ(j,i,1:nLevels)*water_g(1:nLevels)*water_w0(1:nLevels) + tauICE(j,i,1:nLevels) * &
                  ice_g(1:nLevels) * ice_w0(1:nLevels)) / (g(j,i,1:nLevels) * tau(1:nLevels))
          end where
       enddo
    enddo
    
    ! Compute the total optical thickness and the proportion due to liquid in each cell
    do i=1,npoints
       where(tauLIQ(i,1:nSubCols,1:nLevels) + tauICE(i,1:nSubCols,1:nLevels) > 0.) 
          fracLIQ(i,1:nSubCols,1:nLevels) = tauLIQ(i,1:nSubCols,1:nLevels)/ &
               (tauLIQ(i,1:nSubCols,1:nLevels) + tauICE(i,1:nSubCols,1:nLevels))
       elsewhere
          fracLIQ(i,1:nSubCols,1:nLevels) = 0._wp
       end  where
    enddo
    
  end subroutine modis_optics
  
  ! ######################################################################################
  ! SUBROUTINE lidar_optics
  ! ######################################################################################
  subroutine lidar_optics(npoints,ncolumns,nlev,npart,ice_type,q_lsliq, q_lsice,     &
                              q_cvliq, q_cvice,ls_radliq,ls_radice,cv_radliq,cv_radice,  &
                              pres,presf,temp,beta_mol,betatot,tau_part,tau_mol,tautot,  &
                              tautot_S_liq,tautot_S_ice,betatot_ice,betatot_liq,         &
                              tautot_ice,tautot_liq)
    ! ####################################################################################
    ! NOTE: Using "grav" from cosp_constants.f90, instead of grav=9.81, introduces
    ! changes of up to 2% in atb532 adn 0.003% in parasolRefl and lidarBetaMol532. 
    ! This also results in  small changes in the joint-histogram, cfadLidarsr532.
    ! ####################################################################################
    
    ! INPUTS
    INTEGER,intent(in) :: & 
         npoints,      & ! Number of gridpoints
         ncolumns,     & ! Number of subcolumns
         nlev,         & ! Number of levels
         npart,        & ! Number of cloud meteors (stratiform_liq, stratiform_ice, conv_liq, conv_ice). 
         ice_type        ! Ice particle shape hypothesis (0 for spheres, 1 for non-spherical)
    REAL(WP),intent(in),dimension(npoints,nlev) :: &
         temp,         & ! Temperature of layer k
         pres,         & ! Pressure at full levels
         ls_radliq,    & ! Effective radius of LS liquid particles (meters)
         ls_radice,    & ! Effective radius of LS ice particles (meters)
         cv_radliq,    & ! Effective radius of CONV liquid particles (meters)
         cv_radice       ! Effective radius of CONV ice particles (meters)
    REAL(WP),intent(in),dimension(npoints,ncolumns,nlev) :: &
         q_lsliq,      & ! LS sub-column liquid water mixing ratio (kg/kg)
         q_lsice,      & ! LS sub-column ice water mixing ratio (kg/kg)
         q_cvliq,      & ! CONV sub-column liquid water mixing ratio (kg/kg)
         q_cvice         ! CONV sub-column ice water mixing ratio (kg/kg)
    REAL(WP),intent(in),dimension(npoints,nlev+1) :: &
         presf           ! Pressure at half levels
    
    ! OUTPUTS
    REAL(WP),intent(out),dimension(npoints,ncolumns,nlev,npart) :: &
         tau_part          !
    REAL(WP),intent(out),dimension(npoints,ncolumns,nlev)       :: &
         betatot,        & ! 
         tautot            ! Optical thickess integrated from top
    REAL(WP),optional,intent(out),dimension(npoints,ncolumns,nlev)       :: &
         betatot_ice,    & ! Backscatter coefficient for ice particles
         betatot_liq,    & ! Backscatter coefficient for liquid particles
         tautot_ice,     & ! Total optical thickness of ice
         tautot_liq        ! Total optical thickness of liq
    REAL(WP),intent(out),dimension(npoints,nlev) :: &
         beta_mol,       & ! Molecular backscatter coefficient
         tau_mol           ! Molecular optical depth
    REAL(WP),intent(out),dimension(npoints,ncolumns) :: &
         tautot_S_liq,   & ! TOA optical depth for liquid
         tautot_S_ice      ! TOA optical depth for ice
    
    ! LOCAL VARIABLES
    REAL(WP),dimension(npart)                       :: rhopart
    REAL(WP),dimension(npart,5)                     :: polpart 
    REAL(WP),dimension(npoints,nlev)                :: rhoair,alpha_mol
    REAL(WP),dimension(npoints,nlev+1)              :: zheight          
    REAL(WP),dimension(npoints,nlev,npart)          :: rad_part,kp_part,qpart
    REAL(WP),dimension(npoints,ncolumns,nlev,npart) :: alpha_part
    INTEGER                                         :: i,k,icol
    
    ! Local data
    REAL(WP),PARAMETER :: rhoice     = 0.5e+03    ! Density of ice (kg/m3) 
    REAL(WP),PARAMETER :: Cmol       = 6.2446e-32 ! Wavelength dependent
    REAL(WP),PARAMETER :: rdiffm     = 0.7_wp     ! Multiple scattering correction parameter
    REAL(WP),PARAMETER :: Qscat      = 2.0_wp     ! Particle scattering efficiency at 532 nm
    ! Local indicies for large-scale and convective ice and liquid 
    INTEGER,PARAMETER  :: INDX_LSLIQ = 1
    INTEGER,PARAMETER  :: INDX_LSICE = 2
    INTEGER,PARAMETER  :: INDX_CVLIQ = 3
    INTEGER,PARAMETER  :: INDX_CVICE = 4
    
    ! Polarized optics parameterization
    ! Polynomial coefficients for spherical liq/ice particles derived from Mie theory.
    ! Polynomial coefficients for non spherical particles derived from a composite of
    ! Ray-tracing theory for large particles (e.g. Noel et al., Appl. Opt., 2001)
    ! and FDTD theory for very small particles (Yang et al., JQSRT, 2003).
    ! We repeat the same coefficients for LS and CONV cloud to make code more readable
    REAL(WP),PARAMETER,dimension(5) :: &
         polpartCVLIQ  = (/ 2.6980e-8_wp,  -3.7701e-6_wp,  1.6594e-4_wp,    -0.0024_wp,    0.0626_wp/), &
         polpartLSLIQ  = (/ 2.6980e-8_wp,  -3.7701e-6_wp,  1.6594e-4_wp,    -0.0024_wp,    0.0626_wp/), &
         polpartCVICE0 = (/-1.0176e-8_wp,   1.7615e-6_wp, -1.0480e-4_wp,     0.0019_wp,    0.0460_wp/), &
         polpartLSICE0 = (/-1.0176e-8_wp,   1.7615e-6_wp, -1.0480e-4_wp,     0.0019_wp,    0.0460_wp/), &
         polpartCVICE1 = (/ 1.3615e-8_wp, -2.04206e-6_wp, 7.51799e-5_wp, 0.00078213_wp, 0.0182131_wp/), &
         polpartLSICE1 = (/ 1.3615e-8_wp, -2.04206e-6_wp, 7.51799e-5_wp, 0.00078213_wp, 0.0182131_wp/)
    ! ##############################################################################
    
    ! Liquid/ice particles
    rhopart(INDX_LSLIQ) = rholiq
    rhopart(INDX_LSICE) = rhoice
    rhopart(INDX_CVLIQ) = rholiq
    rhopart(INDX_CVICE) = rhoice
    
    ! LS and CONV Liquid water coefficients
    polpart(INDX_LSLIQ,1:5) = polpartLSLIQ
    polpart(INDX_CVLIQ,1:5) = polpartCVLIQ
    ! LS and CONV Ice water coefficients
    if (ice_type .eq. 0) then
       polpart(INDX_LSICE,1:5) = polpartLSICE0
       polpart(INDX_CVICE,1:5) = polpartCVICE0
    endif
    if (ice_type .eq. 1) then
       polpart(INDX_LSICE,1:5) = polpartLSICE1
       polpart(INDX_CVICE,1:5) = polpartCVICE1
    endif
    
    ! Effective radius particles:
    rad_part(1:npoints,1:nlev,INDX_LSLIQ) = ls_radliq(1:npoints,1:nlev)
    rad_part(1:npoints,1:nlev,INDX_LSICE) = ls_radice(1:npoints,1:nlev)
    rad_part(1:npoints,1:nlev,INDX_CVLIQ) = cv_radliq(1:npoints,1:nlev)
    rad_part(1:npoints,1:nlev,INDX_CVICE) = cv_radice(1:npoints,1:nlev)    
    rad_part(1:npoints,1:nlev,1:npart)    = MAX(rad_part(1:npoints,1:nlev,1:npart),0._wp)
    rad_part(1:npoints,1:nlev,1:npart)    = MIN(rad_part(1:npoints,1:nlev,1:npart),70.0e-6_wp)
    
    ! Density (clear-sky air)
    rhoair(1:npoints,1:nlev) = pres(1:npoints,1:nlev)/(rd*temp(1:npoints,1:nlev))
    
    ! Altitude at half pressure levels:
    zheight(1:npoints,nlev+1) = 0._wp
    do k=nlev,1,-1
       zheight(1:npoints,k) = zheight(1:npoints,k+1) &
            -(presf(1:npoints,k)-presf(1:npoints,k+1))/(rhoair(1:npoints,k)*grav)
    enddo
    
    ! ##############################################################################
    ! *) Molecular alpha, beta and optical thickness
    ! ##############################################################################
    
    beta_mol(1:npoints,1:nlev)  = pres(1:npoints,1:nlev)/km/temp(1:npoints,1:nlev)*Cmol
    alpha_mol(1:npoints,1:nlev) = 8._wp*pi/3._wp * beta_mol(1:npoints,1:nlev)
    
    ! Optical thickness of each layer (molecular)  
    tau_mol(1:npoints,1:nlev) = alpha_mol(1:npoints,1:nlev)*(zheight(1:npoints,1:nlev)-&
         zheight(1:npoints,2:nlev+1))
    
    ! Optical thickness from TOA to layer k (molecular)
    DO k = 2,nlev
       tau_mol(1:npoints,k) = tau_mol(1:npoints,k) + tau_mol(1:npoints,k-1)
    ENDDO
    
    betatot    (1:npoints,1:ncolumns,1:nlev) = spread(beta_mol(1:npoints,1:nlev), dim=2, NCOPIES=ncolumns)
    tautot     (1:npoints,1:ncolumns,1:nlev) = spread(tau_mol (1:npoints,1:nlev), dim=2, NCOPIES=ncolumns)
    if (present(betatot_ice) .and. present(betatot_liq) .and. present(tautot_ice) .and. present(tautot_liq)) then
       betatot_liq(1:npoints,1:ncolumns,1:nlev) = betatot(1:npoints,1:ncolumns,1:nlev)
       betatot_ice(1:npoints,1:ncolumns,1:nlev) = betatot(1:npoints,1:ncolumns,1:nlev)
       tautot_liq (1:npoints,1:ncolumns,1:nlev) = tautot(1:npoints,1:ncolumns,1:nlev)
       tautot_ice (1:npoints,1:ncolumns,1:nlev) = tautot(1:npoints,1:ncolumns,1:nlev)
    endif
    
    ! ##############################################################################
    ! *) Particles alpha, beta and optical thickness
    ! ##############################################################################
    ! Polynomials kp_lidar derived from Mie theory
    do i = 1, npart
       where (rad_part(1:npoints,1:nlev,i) .gt. 0.0)
          kp_part(1:npoints,1:nlev,i) = &
               polpart(i,1)*(rad_part(1:npoints,1:nlev,i)*1e6)**4 &
               + polpart(i,2)*(rad_part(1:npoints,1:nlev,i)*1e6)**3 &
               + polpart(i,3)*(rad_part(1:npoints,1:nlev,i)*1e6)**2 &
               + polpart(i,4)*(rad_part(1:npoints,1:nlev,i)*1e6) &
               + polpart(i,5)
       elsewhere
          kp_part(1:npoints,1:nlev,i) = 0._wp
       endwhere
    enddo
    
    ! Loop over all subcolumns
    do icol=1,ncolumns
       ! ##############################################################################
       ! Mixing ratio particles in each subcolum
       ! ##############################################################################
       qpart(1:npoints,1:nlev,INDX_LSLIQ) = q_lsliq(1:npoints,icol,1:nlev)
       qpart(1:npoints,1:nlev,INDX_LSICE) = q_lsice(1:npoints,icol,1:nlev)
       qpart(1:npoints,1:nlev,INDX_CVLIQ) = q_cvliq(1:npoints,icol,1:nlev)
       qpart(1:npoints,1:nlev,INDX_CVICE) = q_cvice(1:npoints,icol,1:nlev)
       
       ! ##############################################################################
       ! Alpha and optical thickness (particles)
       ! ##############################################################################
       ! Alpha of particles in each subcolumn:
       do i = 1, npart
          where (rad_part(1:npoints,1:nlev,i) .gt. 0.0)
             alpha_part(1:npoints,icol,1:nlev,i) = 3._wp/4._wp * Qscat &
                  * rhoair(1:npoints,1:nlev) * qpart(1:npoints,1:nlev,i) &
                  / (rhopart(i) * rad_part(1:npoints,1:nlev,i) )
          elsewhere
             alpha_part(1:npoints,icol,1:nlev,i) = 0._wp
          endwhere
       enddo
       
       ! Optical thicknes
       tau_part(1:npoints,icol,1:nlev,1:npart) = rdiffm * alpha_part(1:npoints,icol,1:nlev,1:npart)
       do i = 1, npart
          ! Optical thickness of each layer (particles)
          tau_part(1:npoints,icol,1:nlev,i) = tau_part(1:npoints,icol,1:nlev,i) &
               & * (zheight(1:npoints,1:nlev)-zheight(1:npoints,2:nlev+1) )
          ! Optical thickness from TOA to layer k (particles)
          do k=2,nlev
             tau_part(1:npoints,icol,k,i) = tau_part(1:npoints,icol,k,i) + tau_part(1:npoints,icol,k-1,i)
          enddo
       enddo
       
       ! ##############################################################################
       ! Beta and optical thickness (total=molecular + particules)
       ! ##############################################################################
       
       DO i = 1, npart
          betatot(1:npoints,icol,1:nlev) = betatot(1:npoints,icol,1:nlev) + &
               kp_part(1:npoints,1:nlev,i)*alpha_part(1:npoints,icol,1:nlev,i)
          tautot(1:npoints,icol,1:nlev) = tautot(1:npoints,icol,1:nlev)  + &
               tau_part(1:npoints,icol,1:nlev,i)
       ENDDO
       
       ! ##############################################################################
       ! Beta and optical thickness (liquid/ice)
       ! ##############################################################################
       if (present(betatot_ice) .and. present(betatot_liq) .and. present(tautot_ice) .and. present(tautot_liq)) then
          ! Ice
          betatot_ice(1:npoints,icol,1:nlev) = betatot_ice(1:npoints,icol,1:nlev)+ &
               kp_part(1:npoints,1:nlev,INDX_LSICE)*alpha_part(1:npoints,icol,1:nlev,INDX_LSICE)+ &
               kp_part(1:npoints,1:nlev,INDX_CVICE)*alpha_part(1:npoints,icol,1:nlev,INDX_CVICE)
          tautot_ice(1:npoints,icol,1:nlev) = tautot_ice(1:npoints,icol,1:nlev)  + &
               tau_part(1:npoints,icol,1:nlev,INDX_LSICE) + &
               tau_part(1:npoints,icol,1:nlev,INDX_CVICE)
          
          ! Liquid
          betatot_liq(1:npoints,icol,1:nlev) = betatot_liq(1:npoints,icol,1:nlev)+ &
               kp_part(1:npoints,1:nlev,INDX_LSLIQ)*alpha_part(1:npoints,icol,1:nlev,INDX_LSLIQ)+ &
               kp_part(1:npoints,1:nlev,INDX_CVLIQ)*alpha_part(1:npoints,icol,1:nlev,INDX_CVLIQ)
          tautot_liq(1:npoints,icol,1:nlev) = tautot_liq(1:npoints,icol,1:nlev)  + &
               tau_part(1:npoints,icol,1:nlev,INDX_LSLIQ) + &
               tau_part(1:npoints,icol,1:nlev,INDX_CVLIQ)
       endif
    enddo
    
    ! ##############################################################################    
    ! Optical depths used by the PARASOL simulator
    ! ##############################################################################   
    tautot_S_liq(1:npoints,1:ncolumns) = 0._wp
    tautot_S_ice(1:npoints,1:ncolumns) = 0._wp
    do icol=1,ncolumns    
       tautot_S_liq(1:npoints,icol) = tautot_S_liq(1:npoints,icol)+tau_part(1:npoints,icol,nlev,1)+tau_part(1:npoints,icol,nlev,3)
       tautot_S_ice(1:npoints,icol) = tautot_S_ice(1:npoints,icol)+tau_part(1:npoints,icol,nlev,2)+tau_part(1:npoints,icol,nlev,4)
    enddo
    
  end subroutine lidar_optics
  
  ! ########################################################################################
  ! Optical functions used by MODIS_OPTICS
  ! ########################################################################################
  elemental function get_g_nir (phase, re)
    ! Polynomial fit for asummetry parameter g in MODIS band 7 (near IR) as a function 
    ! of size for ice and water
    ! Fits from Steve Platnick
    
    ! INPUTS
    integer, intent(in) :: phase
    real(wp),intent(in) :: re
    ! OUTPUTS
    real(wp)            :: get_g_nir 
    ! LOCAL VARIABLES(parameters)
    real(wp), dimension(3), parameter :: &
         ice_coefficients         = (/ 0.7432,  4.5563e-3, -2.8697e-5 /), & 
         small_water_coefficients = (/ 0.8027, -1.0496e-2,  1.7071e-3 /), & 
         big_water_coefficients   = (/ 0.7931,  5.3087e-3, -7.4995e-5 /) 
    
    ! approx. fits from MODIS Collection 5 LUT scattering calculations
    if(phase == phaseIsLiquid) then
       if(re < 8.) then 
          get_g_nir = fit_to_quadratic(re, small_water_coefficients)
          if(re < re_water_min) get_g_nir = fit_to_quadratic(re_water_min, small_water_coefficients)
       else
          get_g_nir = fit_to_quadratic(re,   big_water_coefficients)
          if(re > re_water_max) get_g_nir = fit_to_quadratic(re_water_max, big_water_coefficients)
       end if
    else
       get_g_nir = fit_to_quadratic(re, ice_coefficients)
       if(re < re_ice_min) get_g_nir = fit_to_quadratic(re_ice_min, ice_coefficients)
       if(re > re_ice_max) get_g_nir = fit_to_quadratic(re_ice_max, ice_coefficients)
    end if
    
  end function get_g_nir
  elemental function get_ssa_nir (phase, re)
    ! Polynomial fit for single scattering albedo in MODIS band 7 (near IR) as a function 
    !   of size for ice and water
    ! Fits from Steve Platnick
    
    ! INPUTS
    integer, intent(in) :: phase
    real(wp),intent(in) :: re
    ! OUTPUTS
    real(wp)            :: get_ssa_nir
    ! LOCAL VARIABLES (parameters)
    real(wp), dimension(4), parameter :: ice_coefficients   = (/ 0.9994, -4.5199e-3, 3.9370e-5, -1.5235e-7 /)
    real(wp), dimension(3), parameter :: water_coefficients = (/ 1.0008, -2.5626e-3, 1.6024e-5 /) 
    
    ! approx. fits from MODIS Collection 5 LUT scattering calculations
    if(phase == phaseIsLiquid) then
       get_ssa_nir = fit_to_quadratic(re, water_coefficients)
       if(re < re_water_min) get_ssa_nir = fit_to_quadratic(re_water_min, water_coefficients)
       if(re > re_water_max) get_ssa_nir = fit_to_quadratic(re_water_max, water_coefficients)
    else
       get_ssa_nir = fit_to_cubic(re, ice_coefficients)
       if(re < re_ice_min) get_ssa_nir = fit_to_cubic(re_ice_min, ice_coefficients)
       if(re > re_ice_max) get_ssa_nir = fit_to_cubic(re_ice_max, ice_coefficients)
    end if
    
  end function get_ssa_nir
  pure function fit_to_cubic(x, coefficients) 
    ! INPUTS
    real(wp),               intent(in) :: x
    real(wp), dimension(4), intent(in) :: coefficients
    ! OUTPUTS
    real(wp)                           :: fit_to_cubic  
    
    fit_to_cubic = coefficients(1) + x * (coefficients(2) + x * (coefficients(3) + x * coefficients(4)))
  end function fit_to_cubic
  pure function fit_to_quadratic(x, coefficients) 
    ! INPUTS
    real(wp),               intent(in) :: x
    real(wp), dimension(3), intent(in) :: coefficients
    ! OUTPUTS
    real(wp)                           :: fit_to_quadratic
    
    fit_to_quadratic = coefficients(1) + x * (coefficients(2) + x * (coefficients(3)))
  end function fit_to_quadratic
  
end module cosp_optics
