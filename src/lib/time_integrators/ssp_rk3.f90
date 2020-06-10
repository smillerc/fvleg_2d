module mod_ssp_rk3
  !< Summary:  Module that providse the implementation of the 3rd order SSP Runge-Kutta
  !<           time integration
  !< Date: 06/09/2020
  !< Author: Sam Miller
  !< Notes:
  !< References:
  !<     [1] S. Gottlieb, CW Shu, E. Tadmor, "Strong Stability-Preservin gHigh-Order Time Discretization Methods",
  !<      https://doi.org/10.1137/S003614450036757X

  use, intrinsic :: iso_fortran_env, only: ik => int32, rk => real64
  use mod_globals, only: debug_print
  use mod_surrogate, only: surrogate
  use mod_strategy, only: strategy
  use mod_integrand, only: integrand_t
  use mod_finite_volume_schemes, only: finite_volume_scheme_t

  implicit none
  private
  public :: ssp_rk3_t

  type, extends(strategy) :: ssp_rk3_t
    !< 3rd-order strong stability preserving RK tmie integration
  contains
    procedure, nopass :: integrate ! integration procedure
  end type

contains

  subroutine integrate(U, finite_volume_scheme, dt)
    !< Time integrator implementation. . See Eq. 4.2 in [1]
    class(surrogate), intent(inout) :: U
    class(finite_volume_scheme_t), intent(inout) :: finite_volume_scheme
    real(rk), intent(inout) :: dt
    class(integrand_t), allocatable :: U_1 !< first stage
    class(integrand_t), allocatable :: U_2 !< second stage
    class(integrand_t), allocatable :: R !< hist

    call debug_print('Running ssp_rk3_t%integrate()', __FILE__, __LINE__)

    select type(U)
    class is(integrand_t)
      allocate(U_1, source=U)
      allocate(U_2, source=U)
      allocate(R, source=U)

      ! 1st stage
      U_1 = U + dt * U%t(finite_volume_scheme, stage=1)
      call U_1%residual_smoother()

      ! 2nd stage
      U_2 = (3.0_rk / 4.0_rk) * U &
            + (1.0_rk / 4.0_rk) * U_1 &
            + (1.0_rk / 4.0_rk) * dt * U_1%t(finite_volume_scheme, stage=2)
      call U_2%residual_smoother()

      ! Final stage
      U = (1.0_rk / 3.0_rk) * U &
          + (2.0_rk / 3.0_rk) * U_2 &
          + (2.0_rk / 3.0_rk) * dt * U_2%t(finite_volume_scheme, stage=3)
      call U%residual_smoother()

      ! Convergence history
      R = U - U_1
      call R%write_residual_history(finite_volume_scheme)

      deallocate(R)
      deallocate(U_1)
      deallocate(U_2)
    class default
      error stop 'Error in ssp_rk3_t%integrate - unsupported class'
    end select

  end subroutine
end module mod_ssp_rk3