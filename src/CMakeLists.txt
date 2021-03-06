# Add third party libraries
include_directories(${HDF5_INCLUDE_DIRS})

add_subdirectory(third_party)

# Pre-process: .fypp -> .f90 via Fypp Create a list of the files to be preprocessed
set(fyppFiles
    lib/spatial_reconstruction/muscl_tvd2.fypp
    lib/spatial_reconstruction/muscl_tvd3.fypp 
    lib/spatial_reconstruction/muscl_tvd5.fypp
    lib/spatial_reconstruction/muscl_e_mlp.fypp
    lib/spatial_reconstruction/muscl_mlp.fypp
    lib/boundary_conditions/periodic_bc.fypp
    lib/limiters/e_mlp_distinguisher.fypp
    lib/flux_solvers/m_ausmpw_plus_solver.fypp
    lib/flux_solvers/ausmpw_plus_solver.fypp
    lib/flux_solvers/roe_solver.fypp
    lib/flux_solvers/slau_solver.fypp
)

# Pre-process
foreach(infileName IN LISTS fyppFiles)

  # Generate output file name
  string(REGEX REPLACE ".fypp\$" ".f90" outfileName "${infileName}")
  # Generate input file name
  set(infile "${CMAKE_CURRENT_SOURCE_DIR}/${infileName}")

  # Create the full path for the new file
  get_filename_component(f90_file ${outfileName} NAME)
  set(outfile "${CMAKE_BINARY_DIR}/generated/${f90_file}")

  # Custom command to do the processing
  add_custom_command(
    OUTPUT "${outfile}"
    COMMAND fypp "${infile}" "${outfile}"
    MAIN_DEPENDENCY "${infile}"
    VERBATIM)

  # Finally add output file to a list
  set(outFiles ${outFiles} "${outfile}")

endforeach(infileName)

add_library(
  cato
  ${outFiles}
  lib/error.f90
  lib/units.f90
  lib/globals.f90
  lib/mod_parallel.f90
  lib/mod_collectives.f90
  lib/non_dimensional.f90
  lib/math_constants.f90
  lib/floating_point_utilities.f90
  lib/field/field_2d.f90
  lib/field/field_2d_cpu_operators.f90
  lib/field/field_2d_gpu_operators.f90
  lib/equation_of_state.f90
  lib/limiters/slope_limiter.f90
  lib/limiters/flux_limiter.f90
  lib/io/mod_hdf5.f90
  lib/io/mod_input.f90
  lib/grid/grid_block.f90
  # lib/grid/grid_block_1d.f90
  lib/grid/grid_block_2d.f90
  # lib/grid/grid_block_3d.f90
  lib/grid/grid_factory.f90
  lib/geometry/geometry.f90
  lib/geometry/intersections.f90
  lib/geometry/vector_2d.f90
  lib/geometry/vector.f90
  lib/geometry/quad_cell.f90
  # lib/mach_cone/mach_cone_utilities.f90
  # lib/mach_cone/mach_cone_collection.f90
  lib/mod_timing.f90
  lib/io/contour_writer.f90
  lib/boundary_conditions/boundary_conditions.f90
  lib/boundary_conditions/zero_gradient_bc.f90
  lib/boundary_conditions/inlet_outlet.f90
  lib/boundary_conditions/pressure_input_bc.f90
  lib/boundary_conditions/symmetry_bc.f90
  lib/boundary_conditions/outlet_bc.f90
  lib/boundary_conditions/bc_factory.f90
  lib/source_terms/source_factory.f90
  lib/source_terms/mod_source.f90
  lib/source_terms/energy_source.f90
  lib/fluid/flux_array.f90
  lib/fluid/mod_fluid.f90
  lib/flux_solvers/flux_solver.f90
  # lib/flux_solvers/fvleg_solver.f90
  # lib/flux_solvers/ausm_plus_solver.f90
  # lib/evolution_operator/local_evo_operator.f90
  # lib/spatial_reconstruction/abstract_reconstruction.f90
  # lib/spatial_reconstruction/gradients.f90
  # lib/spatial_reconstruction/piecewise_constant.f90
  # lib/spatial_reconstruction/piecewise_linear.f90
  # lib/spatial_reconstruction/edge_interpolator.f90
  # lib/spatial_reconstruction/edge_interpolator_factory.f90
  # lib/spatial_reconstruction/tvd_2nd_order.f90
  # lib/spatial_reconstruction/tvd_3rd_order.f90
  # lib/spatial_reconstruction/tvd_5th_order.f90
  # lib/spatial_reconstruction/reconstruction_factory.f90
  lib/spatial_reconstruction/muscl_interpolation.f90
  lib/spatial_reconstruction/muscl_factory.f90
  lib/master_puppeteer/master_puppeteer.f90)

target_link_libraries(cato PUBLIC h5fortran functional finterp ini_parser ${HDF5_LIBRARIES} ${HDF5_HL_LIBRARIES} ${Coarray_LIBRARIES})

add_executable(cato.x main.f90)
target_link_libraries(cato.x PUBLIC cato ${Coarray_LIBRARIES})