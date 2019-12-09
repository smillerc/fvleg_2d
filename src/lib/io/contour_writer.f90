module mod_contour_writer

  use iso_fortran_env, only: ik => int32, rk => real64, real32
  use mod_finite_volume_schemes, only: finite_volume_scheme_t
  use hdf5_interface, only: hdf5_file
  use mod_functional, only: operator(.reverse.)
  use mod_globals, only: compiler_flags_str, compiler_version_str, git_hash, git_ref, &
                         git_local_changes, fvleg_2d_version, &
                         compile_host, compile_os, build_type, set_global_options, globals_set

  implicit none

  private
  public :: contour_writer_t

  type :: contour_writer_t
    !< Type that manages writing out data to hdf5
    private
    type(hdf5_file) :: hdf5_file
    character(len=:), allocatable :: hdf5_filename
    character(len=:), allocatable :: xdmf_filename
  contains
    procedure, public :: write_contour
    procedure, private :: write_xdmf
    procedure, private :: write_hdf5
  end type

contains
  subroutine write_contour(self, fv_scheme, time, iteration)
    class(contour_writer_t), intent(inout) :: self
    class(finite_volume_scheme_t), intent(in) :: fv_scheme
    integer(ik), intent(in) :: iteration
    real(rk), intent(in) :: time
    character(50) :: char_buff

    write(char_buff, '(a,i0.7)') 'step_', iteration
    self%hdf5_filename = trim(char_buff)//'.h5'
    self%xdmf_filename = trim(char_buff)//'.xdmf'

    call self%write_hdf5(fv_scheme, time, iteration)
    call self%write_xdmf(fv_scheme, time, iteration)

  end subroutine

  subroutine write_hdf5(self, fv_scheme, time, iteration)
    class(contour_writer_t), intent(inout) :: self
    class(finite_volume_scheme_t), intent(in) :: fv_scheme
    integer(ik), intent(in) :: iteration
    real(rk), intent(in) :: time
    character(50) :: char_buff

    sync all
    if(this_image() == 1) then

      call self%hdf5_file%initialize(filename=self%hdf5_filename, &
                                     status='new', action='w', comp_lvl=6)

      ! Header info
      call self%hdf5_file%add('/title', fv_scheme%title)

      call self%hdf5_file%add('/iteration', iteration)
      call self%hdf5_file%writeattr('/iteration', 'description', 'Iteration Count')
      call self%hdf5_file%writeattr('/iteration', 'units', 'dimensionless')

      call self%hdf5_file%add('/time', real(time, real32))
      call self%hdf5_file%writeattr('/time', 'description', 'Simulation Time')
      call self%hdf5_file%writeattr('/time', 'units', 'seconds')

      call self%hdf5_file%add('/delta_t', fv_scheme%delta_t)
      call self%hdf5_file%writeattr('/delta_t', 'description', 'Simulation Timestep')
      call self%hdf5_file%writeattr('/delta_t', 'units', 'seconds')

      ! Version info
      if(.not. globals_set) call set_global_options()
      call self%hdf5_file%writeattr('/', 'compiler_flags', compiler_flags_str)
      call self%hdf5_file%writeattr('/', 'compiler_version', compiler_version_str)
      call self%hdf5_file%writeattr('/', 'git_hast', git_hash)
      call self%hdf5_file%writeattr('/', 'git_ref', git_ref)
      call self%hdf5_file%writeattr('/', 'git_changes', git_local_changes)
      call self%hdf5_file%writeattr('/', 'version', fvleg_2d_version)
      call self%hdf5_file%writeattr('/', 'compile_hostname', compile_host)
      call self%hdf5_file%writeattr('/', 'compile_os', compile_os)
      call self%hdf5_file%writeattr('/', 'build_type', build_type)

      ! Grid
      call self%hdf5_file%add('/x', real(fv_scheme%grid%node_x, real32))
      call self%hdf5_file%writeattr('/x', 'description', 'X Coordinate')
      call self%hdf5_file%writeattr('/x', 'units', 'cm')

      call self%hdf5_file%add('/y', real(fv_scheme%grid%node_y, real32))
      call self%hdf5_file%writeattr('/y', 'description', 'Y Coordinate')
      call self%hdf5_file%writeattr('/y', 'units', 'cm')

      call self%hdf5_file%add('/volume', real(fv_scheme%grid%cell_volume, real32))
      call self%hdf5_file%writeattr('/volume', 'description', 'Cell Volume')
      call self%hdf5_file%writeattr('/volume', 'units', 'cc')

      ! Conserved Variables
      call self%hdf5_file%add('/density', real(fv_scheme%conserved_vars(1, :, :), real32))
      call self%hdf5_file%writeattr('/density', 'description', 'Cell Density')
      call self%hdf5_file%writeattr('/density', 'units', 'g/cc')

      call self%hdf5_file%add('/x_velocity', real(fv_scheme%conserved_vars(2, :, :), real32))
      call self%hdf5_file%writeattr('/x_velocity', 'description', 'Cell X Velocity')
      call self%hdf5_file%writeattr('/x_velocity', 'units', 'cm/s')

      call self%hdf5_file%add('/y_velocity', real(fv_scheme%conserved_vars(3, :, :), real32))
      call self%hdf5_file%writeattr('/y_velocity', 'description', 'Cell Y Velocity')
      call self%hdf5_file%writeattr('/y_velocity', 'units', 'cm/s')

      call self%hdf5_file%add('/pressure', real(fv_scheme%conserved_vars(4, :, :), real32))
      call self%hdf5_file%writeattr('/pressure', 'description', 'Cell Pressure')
      call self%hdf5_file%writeattr('/pressure', 'units', 'barye')

      ! Source Terms (if any)

      ! Inputs
      call self%hdf5_file%finalize()
    end if
  end subroutine

  subroutine write_xdmf(self, fv_scheme, time, iteration)
    class(contour_writer_t), intent(inout) :: self
    class(finite_volume_scheme_t), intent(in) :: fv_scheme
    integer(ik), intent(in) :: iteration
    real(rk), intent(in) :: time
    integer(ik) :: xdmf_unit
    character(50) :: char_buff
    character(:), allocatable :: cell_shape, node_shape

    open(newunit=xdmf_unit, file=self%xdmf_filename, status='replace')

    write(char_buff, '(2(i0,1x))') .reverse.shape(fv_scheme%conserved_vars(1, :, :))
    cell_shape = trim(char_buff)

    write(char_buff, '(2(i0,1x))') .reverse.shape(fv_scheme%grid%node_x)
    node_shape = trim(char_buff)

    write(xdmf_unit, '(a)') '<?xml version="1.0" ?>'
    write(xdmf_unit, '(a)') '<Xdmf version="2.2">'
    write(xdmf_unit, '(a)') '  <Domain>'
    write(xdmf_unit, '(a)') '    <Grid GridType="Uniform" Name="grid">'
    write(xdmf_unit, '(a,g0.3,a)') '      <Time Value="', time, ' second"/>'
    write(xdmf_unit, '(a)') '      <Topology NumberOfElements="'//node_shape//'" TopologyType="2DSMesh"/>'

    write(xdmf_unit, '(a)') '      <Geometry GeometryType="X_Y">'
    write(xdmf_unit, '(a)')'        <DataItem Dimensions="'//node_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/x</DataItem>'
    write(xdmf_unit, '(a)')'        <DataItem Dimensions="'//node_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/y</DataItem>'
    write(xdmf_unit, '(a)') '      </Geometry>'

    write(xdmf_unit, '(a)') '      <Attribute AttributeType="Scalar" Center="Cell" Name="Volume [cc]">'
    write(xdmf_unit, '(a)') '        <DataItem Dimensions="'//cell_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/volume</DataItem>'
    write(xdmf_unit, '(a)') '      </Attribute>'

    write(xdmf_unit, '(a)') '      <Attribute AttributeType="Scalar" Center="Cell" Name="Density [g/cc]">'
    write(xdmf_unit, '(a)') '        <DataItem Dimensions="'//cell_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/density</DataItem>'
    write(xdmf_unit, '(a)') '      </Attribute>'

    write(xdmf_unit, '(a)') '      <Attribute AttributeType="Scalar" Center="Cell" Name="X Velocity [cm/s]">'
    write(xdmf_unit, '(a)') '        <DataItem Dimensions="'//cell_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/x_velocity</DataItem>'
    write(xdmf_unit, '(a)') '      </Attribute>'

    write(xdmf_unit, '(a)') '      <Attribute AttributeType="Scalar" Center="Cell" Name="Y Velocity [cm/s]">'
    write(xdmf_unit, '(a)') '        <DataItem Dimensions="'//cell_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/y_velocity</DataItem>'
    write(xdmf_unit, '(a)') '      </Attribute>'

    write(xdmf_unit, '(a)') '      <Attribute AttributeType="Scalar" Center="Cell" Name="Pressure [barye]">'
    write(xdmf_unit, '(a)') '        <DataItem Dimensions="'//cell_shape//'" Format="HDF" NumberType="Float" Precision="4">' // self%hdf5_filename // ':/pressure</DataItem>'
    write(xdmf_unit, '(a)') '      </Attribute>'

    write(xdmf_unit, '(a)') '    </Grid>'
    write(xdmf_unit, '(a)') '  </Domain>'
    write(xdmf_unit, '(a)') '</Xdmf>'
    close(xdmf_unit)

    deallocate(cell_shape)
    deallocate(node_shape)
  end subroutine
end module mod_contour_writer