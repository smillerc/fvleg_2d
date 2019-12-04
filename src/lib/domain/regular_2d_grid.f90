module mod_regular_2d_grid
  use iso_fortran_env, only: ik => int32, rk => real64
  use mod_grid, only: grid_t
  use mod_quad_cell, only: quad_cell_t
  use mod_input, only: input_t

  implicit none

  private
  public :: regular_2d_grid_t

  type, extends(grid_t) :: regular_2d_grid_t
    !< Summary: The regular_2d_grid_t type holds all of the geometry info relevant to the grid.

    ! real(rk), dimension(:, :, :, :, :), allocatable :: cell_edge_vectors
    !< (x:y, loc1:loc2, face1:face4, i, j)
    !< This describes the point locations of the set of edge vectors at each location the mach cone is evaluated.
    !< For instance, for edge E1, a mach cone is constructed at N1, M1, and N2.
    !< At the corner location 1 at N1, e.g. index `loc1`, or k=1,1 (in paper lingo), the 3 points that define the 2
    !< edge vectors are N2, N1, and N4 or (N2,N1) and (N4,N1). To take advantage of memory access patterns, since
    !< mach cones are made 12x at each cell for each timestep, these points are lumped into a big array. The index
    !< loc1:loc2 spans the 1st corner, midpoint, and 2nd corner.

    ! k=1,1 -> [N2, N1, N4]
    ! k=1,c -> [N2, M1, N1]
    ! k=1,2 -> [N3, N2, N1]

    ! k=2,1 -> [N3, N2, N1]
    ! k=2,c -> [N3, M2, N2]
    ! k=2,2 -> [N4, N3, N2]

    ! k=3,1 -> [N4, N3, N2]
    ! k=3,c -> [N4, M3, N3]
    ! k=3,2 -> [N1, N4, N3]

    ! k=4,1 -> [N1, N4, N3]
    ! k=4,c -> [N1, M4, N4]
    ! k=4,2 -> [N2, N1, N4]
  contains
    procedure, public :: initialize
    procedure, private :: populate_element_specifications
    ! procedure, public :: get_ihi
    ! procedure, public :: get_ilo
    ! procedure, public :: get_jlo
    ! procedure, public :: get_jhi
    ! procedure, public :: get_ni
    ! procedure, public :: get_nj
    ! procedure, public :: get_xmin
    ! procedure, public :: get_xmax
    ! procedure, public :: get_ymin
    ! procedure, public :: get_ymax
    ! procedure, public :: get_x_length
    ! procedure, public :: get_y_length
    procedure, public :: get_x
    procedure, public :: get_y
    ! procedure, public :: get_dx
    ! procedure, public :: get_dy
    procedure, public :: get_cell_volumes
    procedure, public :: get_cell_centroid_xy
    procedure, public :: get_cell_edge_lengths
    ! procedure, public :: get_cell_node_xy
    procedure, public :: get_cell_edge_norm_vectors
    procedure, public :: get_midpoint_vectors
    procedure, public :: get_corner_vectors
    procedure, public :: finalize

    final :: force_finalization

  end type regular_2d_grid_t

contains

  subroutine initialize(self, input)

    class(regular_2d_grid_t), intent(inout) :: self
    class(input_t), intent(in) :: input

    integer(ik) :: alloc_status, i, j

    ! Low node/cell indices (always starts at 1)
    self%ilo_node = 1
    self%jlo_node = 1
    self%ilo_cell = 1
    self%jlo_cell = 1

    ! High node/cell indices
    self%ihi_node = input%ni_nodes
    self%jhi_node = input%nj_nodes
    self%ihi_cell = self%ihi_node - 1
    self%jhi_cell = self%jhi_node - 1

    ! Low i/j boundary condition indices
    self%ilo_bc_node = 0
    self%jlo_bc_node = 0
    self%ilo_bc_cell = 0
    self%jlo_bc_cell = 0

    ! Hihh i/j boundary condition indices
    self%ihi_bc_node = self%ihi_node + 1
    self%jhi_bc_node = self%jhi_node + 1
    self%ihi_bc_cell = self%ihi_cell + 1
    self%jhi_bc_cell = self%jhi_cell + 1

    self%ni_node = input%ni_nodes
    self%nj_node = input%nj_nodes
    self%ni_cell = self%ni_node - 1
    self%nj_cell = self%nj_node - 1

    self%xmin = input%xmin
    self%xmax = input%xmax
    self%ymin = input%ymin
    self%ymax = input%ymax

    self%x_length = abs(self%xmax - self%xmin)
    if(self%x_length <= 0) error stop "grid%x_length <= 0"

    self%y_length = abs(self%ymax - self%ymin)
    if(self%y_length <= 0) error stop "grid%x_length <= 0"

    self%min_dx = self%x_length / real(self%ni_cell, rk)
    self%max_dx = self%min_dx ! placeholder for now
    if(self%min_dx <= 0) error stop "grid%dx <= 0"

    self%min_dy = self%y_length / real(self%nj_cell, rk)
    self%max_dy = self%min_dy ! placeholder for now
    if(self%min_dy <= 0) error stop "grid%dy <= 0"

    ! Allocate node based arrays
    associate(imin=>self%ilo_bc_node, imax=>self%ihi_bc_node, &
              jmin=>self%jlo_bc_node, jmax=>self%jhi_bc_node)

      allocate(self%node_x(imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%node_x"

      allocate(self%node_y(imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%node_y"
    end associate

    ! Set the x spacing
    do i = self%ilo_node, self%ihi_node
      self%node_x(i, :) = self%xmin + (i - 1) * self%min_dx
    end do

    ! Set the low i boundary location
    associate(x_0=>self%node_x(self%ilo_node, :), &
              x_1=>self%node_x(self%ilo_node + 1, :))
      self%node_x(self%ilo_bc_node, :) = x_0 - (x_1 - x_0)
    end associate

    ! Set the high i boundary
    associate(x_n=>self%node_x(self%ihi_node, :), &
              x_n_minus_1=>self%node_x(self%ihi_node - 1, :))
      self%node_x(self%ihi_bc_node, :) = x_n + (x_n - x_n_minus_1)
    end associate

    ! Set the y spacing
    do j = self%jlo_node, self%jhi_node
      self%node_y(:, j) = self%ymin + (j - 1) * self%min_dy
    end do

    ! Set the low j boundary location
    associate(y_0=>self%node_y(:, self%jlo_node), &
              y_1=>self%node_y(:, self%jlo_node + 1))
      self%node_y(:, self%jlo_bc_node) = y_0 - (y_1 - y_0)
    end associate

    ! Set the high j boundary
    associate(y_n=>self%node_y(:, self%jhi_node), &
              y_n_minus_1=>self%node_y(:, self%jhi_node - 1))
      self%node_y(:, self%jhi_bc_node) = y_n + (y_n - y_n_minus_1)
    end associate

    ! Allocate cell based arrays
    associate(imin=>self%ilo_bc_cell, imax=>self%ihi_bc_cell, &
              jmin=>self%jlo_bc_cell, jmax=>self%jhi_bc_cell)

      allocate(self%cell_volume(imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_volume"
      self%cell_volume = 0.0_rk

      allocate(self%cell_centroid_xy(2, imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_centroid_xy"
      self%cell_centroid_xy = 0.0_rk

      allocate(self%cell_edge_lengths(4, imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_edge_lengths"
      self%cell_edge_lengths = 0.0_rk

      ! allocate(self%cell_edge_vectors(2, 3, 4, imin:imax, jmin:jmax), stat=alloc_status)
      ! if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_edge_vectors"
      ! self%cell_edge_vectors = 0.0_rk

      allocate(self%cell_edge_norm_vectors(2, 4, imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_edge_norm_vectors"
      self%cell_edge_norm_vectors = 0.0_rk

      allocate(self%cell_node_xy(2, 4, 2, imin:imax, jmin:jmax), stat=alloc_status)
      if(alloc_status /= 0) error stop "Unable to allocate regular_2d_grid_t%cell_node_xy"
      self%cell_node_xy = 0.0_rk
    end associate

    call self%populate_element_specifications()
  end subroutine

  subroutine populate_element_specifications(self)
    !< Summary: Fill the element arrays up with the geometric information
    !< This seemed to be better for memory access patterns elsewhere in the code. Fortran prefers
    !< and structure of arrays rather than an array of structures

    class(regular_2d_grid_t), intent(inout) :: self
    class(quad_cell_t), allocatable :: quad

    integer(ik) :: i, j

    do j = self%jlo_bc_cell, self%jhi_bc_cell
      do i = self%ilo_bc_cell, self%ihi_bc_cell

        allocate(quad_cell_t :: quad)

        associate(x=>self%node_x, y=>self%node_y)
          call quad%initialize(x_coords=[x(i, j), x(i + 1, j), x(i + 1, j + 1), x(i, j + 1)], &
                               y_coords=[y(i, j), y(i + 1, j), y(i + 1, j + 1), y(i, j + 1)])

        end associate

        self%cell_volume(i, j) = quad%volume
        ! self%cell_centroid_xy(i, j, :) = quad%centroid
        ! self%cell_edge_lengths(i, j, :) = quad%edge_lengths
        ! self%cell_edge_midpoints(i, j, :, :) = quad%edge_midpoints
        ! self%cell_edge_norm_vectors(i, j, :, :) = quad%edge_norm_vectors

        deallocate(quad)

      end do
    end do

  end subroutine

  subroutine force_finalization(self)
    type(regular_2d_grid_t), intent(inout) :: self
    call self%finalize()
  end subroutine

  subroutine finalize(self)
    class(regular_2d_grid_t), intent(inout) :: self
    integer(ik) :: alloc_status

    print *, 'Finalizing regular_2d_grid_t'
    if(allocated(self%cell_volume)) deallocate(self%cell_volume, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%cell_volume"

    if(allocated(self%node_x)) deallocate(self%node_x, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%node_x"

    if(allocated(self%node_y)) deallocate(self%node_y, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%node_y"

    if(allocated(self%cell_centroid_xy)) deallocate(self%cell_centroid_xy, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%cell_centroid_xy"

    if(allocated(self%cell_edge_lengths)) deallocate(self%cell_edge_lengths, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%cell_edge_lengths"

    if(allocated(self%cell_node_xy)) deallocate(self%cell_node_xy, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%cell_node_xy"

    if(allocated(self%cell_edge_norm_vectors)) deallocate(self%cell_edge_norm_vectors, stat=alloc_status)
    if(alloc_status /= 0) error stop "Unable to deallocate regular_2d_grid_t%cell_edge_norm_vectors"

  end subroutine finalize

  ! pure function get_ihi(self) result(ihi)
  !   !< Public interface to get ihi
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: ihi
  !   ihi = self%ihi
  ! end function

  ! pure function get_ilo(self) result(ilo)
  !   !< Public interface to get ilo
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: ilo
  !   ilo = self%ilo
  ! end function

  ! pure function get_ni(self) result(ni)
  !   !< Public interface to get ni
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: ni
  !   ni = self%ni
  ! end function

  ! pure function get_nj(self) result(nj)
  !   !< Public interface to get nj
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: nj
  !   nj = self%nj
  ! end function

  ! pure function get_jlo(self) result(jlo)
  !   !< Public interface to get jlo
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: jlo
  !   jlo = self%jlo
  ! end function

  ! pure function get_jhi(self) result(jhi)
  !   !< Public interface to get jhi
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik) :: jhi
  !   jhi = self%jhi
  ! end function

  ! pure function get_xmin(self) result(xmin)
  !   !< Public interface to get xmin
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: xmin
  !   xmin = self%xmin
  ! end function

  ! pure function get_xmax(self) result(xmax)
  !   !< Public interface to get xmax
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: xmax
  !   xmax = self%xmax
  ! end function

  ! pure function get_ymin(self) result(ymin)
  !   !< Public interface to get ymin
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: ymin
  !   ymin = self%ymin
  ! end function

  ! pure function get_ymax(self) result(ymax)
  !   !< Public interface to get ymax
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: ymax
  !   ymax = self%ymax
  ! end function

  ! pure function get_dx(self) result(dx)
  !   !< Public interface to get ymax
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: dx
  !   dx = self%dx
  ! end function

  ! pure function get_dy(self) result(dy)
  !   !< Public interface to get ymax
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: dy
  !   dy = self%dy
  ! end function

  ! pure function get_x_length(self) result(x_length)
  !   !< Public interface to get x_length
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: x_length
  !   x_length = self%x_length
  ! end function

  ! pure function get_y_length(self) result(y_length)
  !   !< Public interface to get y_length
  !   class(regular_2d_grid_t), intent(in) :: self
  !   real(rk) :: y_length
  !   y_length = self%y_length
  ! end function

  pure function get_x(self, i, j) result(x)
    !< Public interface to get x
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j
    real(rk) :: x
    x = self%node_x(i, j)
  end function

  pure function get_y(self, i, j) result(y)
    !< Public interface to get y
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j
    real(rk) :: y
    y = self%node_y(i, j)
  end function

  pure function get_cell_volumes(self, i, j) result(cell_volume)
    !< Public interface to get cell_volume
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j
    real(rk) :: cell_volume
    cell_volume = self%cell_volume(i, j)
  end function

  pure function get_cell_centroid_xy(self, i, j) result(cell_centroid_xy)
    !< Public interface to get get_cell_centroid_xy
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j
    real(rk), dimension(2) :: cell_centroid_xy
    cell_centroid_xy = self%cell_centroid_xy(:, i, j)
  end function

  pure function get_cell_edge_lengths(self, i, j, f) result(cell_edge_lengths)
    !< Public interface to get cell_edge_lengths
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j, f
    real(rk) :: cell_edge_lengths
    cell_edge_lengths = self%cell_edge_lengths(f, i, j)
  end function

  ! pure function get_cell_node_xy(self, i, j, n, xy) result(cell_node_xy)
  !   !< Public interface to get cell_edge_midpoints
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik), intent(in) :: i, j, n, xy
  !   real(rk) :: cell_node_xy
  !   cell_node_xy = self%cell_node_xy(i, j, n, xy)
  ! end function

  ! pure function get_node_xy_pair(self, i, j, n_id) result(xy_pair)
  !   class(regular_2d_grid_t), intent(in) :: self
  !   integer(ik), intent(in) :: i, j, n_id
  !   real(rk), dimension(2) :: xy_pair

  !   xy_pair = self
  ! end function

  pure function get_cell_edge_norm_vectors(self, i, j, f, xy) result(cell_edge_norm_vectors)
    !< Public interface to get cell_edge_norm_vectors
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), intent(in) :: i, j, f, xy
    real(rk) :: cell_edge_norm_vectors
    cell_edge_norm_vectors = self%cell_edge_norm_vectors(xy, f, i, j)
  end function

  pure function get_midpoint_vectors(self, cell_ij, edge) result(vectors)
    ! // TODO: implement this
    !< Public interface to get_midpoint_vectors
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), dimension(2), intent(in) :: cell_ij
    character(len=*), intent(in) :: edge ! 'bottom', or 'top'
    real(rk), dimension(2, 2, 2) :: vectors !< ((x,y), (head,tail), (vector1, vector2))

    vectors = 0.0_rk
  end function

  pure function get_corner_vectors(self, cell_ij, corner) result(vectors)
    ! // TODO: implement this
    !< Public interface to get_corner_vectors
    class(regular_2d_grid_t), intent(in) :: self
    integer(ik), dimension(2), intent(in) :: cell_ij
    character(len=*), intent(in) :: corner ! 'lowerleft', 'lowerright', 'upperright', 'upperleft'
    real(rk), dimension(2, 2, 4) :: vectors !< ((x,y), (head,tail), (vector1:vector4))

    vectors = 0.0_rk
  end function

end module mod_regular_2d_grid
