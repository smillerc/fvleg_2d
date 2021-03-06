# -*- coding: utf-8 -*-
"""Methods for generating initial grids for cato
in the .h5 format
"""
import numpy as np
import os
import h5py
from configparser import ConfigParser

from .unit_registry import ureg


def get_n_ghost_layers_required(input):
    # Read the input file and make sure the spatial order is consistent
    config = ConfigParser()
    config.read(input)
    config.sections()
    edge_interp = config["scheme"]["limiter"]
    edge_interp = edge_interp.strip("'").strip('"')

    valid_limiters = [
        "minmod",
        "superbee",
        "van_leer",
        "TVD3",
        "TVD5",
        "MLP3",
        "eMLP3",
        "MLP5",
        "eMLP5",
    ]

    if edge_interp not in valid_limiters:
        raise Exception("Invalid limiter type in the input.ini file")

    if edge_interp in ["TVD5", "MLP5", "eMLP5"]:
        n_ghost_layers = 3
    else:
        n_ghost_layers = 2
    return n_ghost_layers


def make_uniform_grid(n_cells, xrange, yrange, input_file="input.ini"):
    """Generate a uniform grid. This will output a dictionary
    that contains the appropriate arrays, which include the ghost
    cell layer.

    Parameters
    ----------
    n_cells : tuple
        Number of non-ghost cells in each direction (x,y)
    xrange : tuple
        Extent of the domain in x (min,max)
    yrange : tuple
        Extent of the domain in y (min,max)

    Returns
    -------
    dictionary
        A dictionary that contains the conserved variables (rho, u velocity, v
        velocity, p), grid (x,y) points, and the cell center (xc,yc) points
    """

    n_ghost_layers = get_n_ghost_layers_required(input_file)

    print(f"Generating grid with {n_ghost_layers} ghost layers")
    dx = float(xrange[1] - xrange[0]) / float(n_cells[0])
    dy = float(yrange[1] - yrange[0]) / float(n_cells[1])

    x = np.linspace(
        start=xrange[0] - n_ghost_layers * dx,
        stop=xrange[1] + n_ghost_layers * dx,
        num=(n_cells[0] + 1) + (n_ghost_layers * 2),
        dtype=np.float64,
    )

    y = np.linspace(
        start=yrange[0] - n_ghost_layers * dy,
        stop=yrange[1] + n_ghost_layers * dy,
        num=(n_cells[1] + 1) + (n_ghost_layers * 2),
        dtype=np.float64,
    )

    xc = np.zeros(x.shape[0] - 1, dtype=np.float64)
    yc = np.zeros(y.shape[0] - 1, dtype=np.float64)

    # 2d versions
    y_2d, x_2d = np.meshgrid(y, x)  # nodes

    # cell-centered arrays
    # node_shape = (x_2d.shape[0], x_2d.shape[1])
    cell_shape = (x_2d.shape[0] - 1, x_2d.shape[1] - 1)
    rho = np.ones(cell_shape)
    u = np.ones(cell_shape)
    v = np.ones(cell_shape)
    p = np.ones(cell_shape)

    # cell center locations
    xc = x_2d[:-1, :-1] + dx / 2.0
    yc = y_2d[:-1, :-1] + dy / 2.0

    return {
        "x": x_2d * ureg("cm"),
        "y": y_2d * ureg("cm"),
        "rho": rho * ureg("g/cc"),
        "u": u * ureg("cm/s"),
        "v": v * ureg("cm/s"),
        "p": p * ureg("barye"),
        "xc": xc * ureg("cm"),
        "yc": yc * ureg("cm"),
        "n_ghost_layers": n_ghost_layers,
    }


def linear_spacing(start, initial_dx, scale, max_dist):
    """Make a 1D array with a specified linear growth in spacing

    Parameters
    ----------
    start : float
        [description]
    initial_dx : float
        [description]
    scale : float
        [description]
    max_dist : float
        [description]

    Returns
    -------
    [type]
        [description]

    Raises
    ------
    Exception
        [description]
    """

    dx = initial_dx
    x = [start]

    if start >= max_dist:
        raise Exception("Error: start >= max_dist")
    while True:
        new_x = x[-1] + dx
        x.append(new_x)
        dx = dx * scale
        if x[-1] > max_dist:
            break
    x = np.array(x, dtype=np.float64)
    dx_last = x[-1] - x[-2]
    dx_first = x[1] - x[0]
    ncells = len(x)
    return x, dx_first, dx_last, ncells


def constant_spacing(start, max_dist, ncells):
    """Make a 1D array with a constant spacing"""
    x = np.linspace(start, max_dist, ncells + 1, endpoint=True)
    end = max_dist
    dx = x[1] - x[0]
    return x, dx, end


def make_2d_layered_grid(
    layer_thicknesses,
    layer_n_cells,
    layer_density,
    layer_u,
    layer_v,
    layer_pressure,
    y_thickness,
    dy=None,
    layer_spacing=None,
    spacing_scale_factor=1.05,
    input_file="input.ini",
):
    """Create a 2D layered grid (uniform in y, layers are in x)

    Parameters
    ----------
    layer_thicknesses : 1d array
        Array with units for the thickness of each layer
    layer_n_cells : list
        List with the number of cells for each layer
    layer_density : 1d array
        Array with units for the density of each layer
    layer_u : 1d array
        Array with units for the x velocity of each layer
    layer_v : 1d array
        Array with units for the y velocity of each layer
    layer_pressure : 1d array
        Array with units for the pressure of each layer
    y_thickness : float with units
        Thickness in the y direction
    dy : float with units, optional
        Spacing in y, by default None
    layer_spacing : List[str], optional
        A list specifying the type of spacing (can be 'constant' or 'linear'), by default None, which means 'constant'
    spacing_scale_factor : float, optional
        Slope for the linear scale tpye, by default 1.05

    Returns
    -------
    dict
        Dictionary of the domain (with units attached to it)

    Raises
    ------
    Exception
        Generic exception if something when wrong
    """
    if not layer_spacing:
        layer_spacing = ["constant"] * len(layer_thicknesses)

    n_ghost_layers = get_n_ghost_layers_required(input_file)
    print(f"Building with {n_ghost_layers} ghost layers")
    layer_thicknesses = layer_thicknesses.to("cm").m
    cumulative_thickness = 0
    dx_last = 0
    total_x = []
    layer_id = 0

    for layer_thickness, ncells, spacing in zip(
        layer_thicknesses, layer_n_cells, layer_spacing
    ):
        start_x = cumulative_thickness
        stop_x = start_x + layer_thickness
        cumulative_thickness = +stop_x
        if spacing == "linear":
            if layer_id == 0:
                raise Exception("Linear spacing not set up for the first layer yet...")
            x, _, _, actual_cells = linear_spacing(
                start=start_x,
                initial_dx=dx_last,
                scale=spacing_scale_factor,
                max_dist=cumulative_thickness,
            )
        else:  # spacing == 'constant':
            x, dx_last, end = constant_spacing(
                start=start_x, max_dist=stop_x, ncells=ncells
            )

        layer_id = layer_id + 1

        if np.any(x):
            total_x.append(x)

    x = np.unique(np.concatenate(total_x)) * ureg("cm")
    x = x.to("cm").m

    # right/left cell size - for making ghost layers
    ldx = x[1] - x[0]
    rdx = x[-1] - x[-2]

    # find the minimum cell spacing
    try:
        y_thickness = y_thickness.to("cm").m
    except AttributeError:
        pass

    if not dy:
        dy = np.diff(x).min()
    else:
        dy = dy.to("cm").m
    n_y_cells = max(1, np.round(y_thickness / dy, 0).astype(int))

    y = np.linspace(
        start=0 - n_ghost_layers * dy,
        stop=y_thickness + n_ghost_layers * dy,
        num=(n_y_cells + 1) + (n_ghost_layers * 2),
        dtype=np.float64,
    )

    # add a ghost cell on either side
    if n_ghost_layers == 1:
        x = np.array([x[0] - ldx] + list(x) + [x[-1] + rdx], dtype=np.float64)
    elif n_ghost_layers == 2:
        x = np.array(
            [x[0] - 2 * ldx]
            + [x[0] - ldx]
            + list(x)
            + [x[-1] + rdx]
            + [x[-1] + 2 * rdx],
            dtype=np.float64,
        )
    elif n_ghost_layers == 3:
        x = np.array(
            [x[0] - 3 * ldx]
            + [x[0] - 2 * ldx]
            + [x[0] - ldx]
            + list(x)
            + [x[-1] + rdx]
            + [x[-1] + 2 * rdx]
            + [x[-1] + 3 * rdx],
            dtype=np.float64,
        )
    else:
        raise Exception("Unable to work with n_ghost_layers that aren't 1 2, or 3")
    dx = np.diff(x) / 2.0
    xc = x[:-1] + dx / 2.0

    layer_cell_idx_ranges = []  # [(first cell, last cell), etc]
    cum_layer_thickness = np.cumsum(layer_thicknesses)
    for layer_idx, l_thick in enumerate(layer_thicknesses):
        if layer_idx == 0:  # first layer
            start_x = x[0]
            end_x = cum_layer_thickness[layer_idx]
        elif layer_idx == len(layer_thicknesses) - 1:  # last layer
            start_x = cum_layer_thickness[layer_idx - 1]
            end_x = x[-1]
        else:  # middle layers
            start_x = cum_layer_thickness[layer_idx - 1]
            end_x = cum_layer_thickness[layer_idx]

        loc = np.where((xc >= start_x) & (xc < end_x))[0]
        start_i = loc[0]
        end_i = loc[-1]
        layer_cell_idx_ranges.append((start_i, end_i))

    # 2d versions
    y_2d, x_2d = np.meshgrid(y, x)  # nodes

    # cell-centered arrays
    # node_shape = (x_2d.shape[0], x_2d.shape[1])
    cell_shape = (x_2d.shape[0] - 1, x_2d.shape[1] - 1)
    rho = np.zeros(cell_shape)
    u = np.zeros(cell_shape)
    v = np.zeros(cell_shape)
    p = np.zeros(cell_shape)

    # Assign rho, u, v, and p to the cell-centered arrays
    for layer_idx, layer in enumerate(layer_cell_idx_ranges):
        if layer_idx == len(layer_cell_idx_ranges):
            s = layer[0]
            e = layer[1]
        else:
            s = layer[0]
            e = -1

        # Convert to cgs units
        rho[s:e, :] = layer_density[layer_idx].to("g/cc").m
        u[s:e, :] = layer_u[layer_idx].to("cm/s").m
        v[s:e, :] = layer_v[layer_idx].to("cm/s").m
        p[s:e, :] = layer_pressure[layer_idx].to("barye").m

    # Assign ghost layer values
    if n_ghost_layers == 1:
        ghost_layers = [0, -1]
    elif n_ghost_layers == 2:
        ghost_layers = [0, 1, -2, -1]
    elif n_ghost_layers == 3:
        ghost_layers = [0, 1, 2, -3, -2, -1]
    else:
        raise Exception("Unable to work with n_ghost_layers that aren't 1 or 2")

    for i in [0, -1]:
        rho[i, :] = layer_density[i].to("g/cc").m
        u[i, :] = layer_u[i].to("cm/s").m
        v[i, :] = layer_v[i].to("cm/s").m
        p[i, :] = layer_pressure[i].to("barye").m

    # cell spacing
    dy = (np.diff(y_2d[0, :]) / 2.0)[0]
    dx = (np.diff(x_2d[:, 0]) / 2.0)[0]

    # cell center locations
    xc = x_2d[:-1, :-1] + dx
    yc = y_2d[:-1, :-1] + dy

    return {
        "x": x_2d * ureg("cm"),
        "y": y_2d * ureg("cm"),
        "rho": rho * ureg("g/cc"),
        "u": u * ureg("cm/s"),
        "v": v * ureg("cm/s"),
        "p": p * ureg("barye"),
        "xc": xc * ureg("cm"),
        "yc": yc * ureg("cm"),
        "n_ghost_layers": n_ghost_layers,
    }


def make_1d_layered_grid(
    layer_thicknesses,
    layer_n_cells,
    layer_density,
    layer_u,
    layer_v,
    layer_pressure,
    layer_spacing=None,
    spacing_scale_factor=1.05,
    input_file="input.ini",
):
    """Create a 1d layered grid

    Parameters
    ----------
    layer_thicknesses : 1d array
        Array with units for the thickness of each layer
    layer_n_cells : list
        List with the number of cells for each layer
    layer_density : 1d array
        Array with units for the density of each layer
    layer_u : 1d array
        Array with units for the x velocity of each layer
    layer_v : 1d array
        Array with units for the y velocity of each layer
    layer_pressure : 1d array
        Array with units for the pressure of each layer

    Returns
    -------
    dictionary
        A dictionary that contains the conserved variables (rho, u velocity, v
        velocity, p), grid points (x, y), and the cell center (xc, yc) points
    """
    n_ghost_layers = get_n_ghost_layers_required(input_file)

    if not layer_spacing:
        layer_spacing = ["constant"] * len(layer_thicknesses)

    layer_thicknesses = layer_thicknesses.to("cm").m
    cumulative_thickness = 0
    dx_last = 0
    total_x = []
    layer_id = 0

    for layer_thickness, ncells, spacing in zip(
        layer_thicknesses, layer_n_cells, layer_spacing
    ):
        start_x = cumulative_thickness
        stop_x = start_x + layer_thickness
        cumulative_thickness = +stop_x
        if spacing == "linear":
            if layer_id == 0:
                raise Exception("Linear spacing not set up for the first layer yet...")
            x, _, _, actual_cells = linear_spacing(
                start=start_x,
                initial_dx=dx_last,
                scale=spacing_scale_factor,
                max_dist=cumulative_thickness,
            )
        else:  # spacing == 'constant':
            x, dx_last, end = constant_spacing(
                start=start_x, max_dist=stop_x, ncells=ncells
            )

        layer_id = layer_id + 1

        if np.any(x):
            total_x.append(x)

    x = np.unique(np.concatenate(total_x)) * ureg("cm")
    x = x.to("cm").m

    # right/left cell size - for making ghost layers
    ldx = x[1] - x[0]
    rdx = x[-1] - x[-2]

    # Since this is a "1d" grid, it needs 3 cells in y
    # (1 on either side for ghost layers)
    y = np.array([-ldx, 0, ldx, ldx * 2], dtype=np.float64) - ldx / 2

    # add a ghost cell on either side
    x = np.array([x[0] - ldx] + list(x) + [x[-1] + rdx], dtype=np.float64)
    dx = np.diff(x) / 2.0
    xc = x[:-1] + dx / 2.0

    layer_cell_idx_ranges = []  # [(first cell, last cell), etc]
    cum_layer_thickness = np.cumsum(layer_thicknesses)
    for layer_idx, l_thick in enumerate(layer_thicknesses):
        if layer_idx == 0:  # first layer
            start_x = x[0]
            end_x = cum_layer_thickness[layer_idx]
        elif layer_idx == len(layer_thicknesses) - 1:  # last layer
            start_x = cum_layer_thickness[layer_idx - 1]
            end_x = x[-1]
        else:  # middle layers
            start_x = cum_layer_thickness[layer_idx - 1]
            end_x = cum_layer_thickness[layer_idx]

        loc = np.where((xc >= start_x) & (xc < end_x))[0]
        start_i = loc[0]
        end_i = loc[-1]
        layer_cell_idx_ranges.append((start_i, end_i))

    # 2d versions
    y_2d, x_2d = np.meshgrid(y, x)  # nodes

    # cell-centered arrays
    rho = np.zeros((x.shape[0] - 1, 3))
    u = np.zeros((x.shape[0] - 1, 3))
    v = np.zeros((x.shape[0] - 1, 3))
    p = np.zeros((x.shape[0] - 1, 3))

    # Assign rho, u, v, and p to the cell-centered arrays
    for layer_idx, layer in enumerate(layer_cell_idx_ranges):
        if layer_idx == len(layer_cell_idx_ranges):
            s = layer[0]
            e = layer[1]
        else:
            s = layer[0]
            e = -1

        # Convert to cgs units
        rho[s:e, :] = layer_density[layer_idx].to("g/cc").m
        u[s:e, :] = layer_u[layer_idx].to("cm/s").m
        v[s:e, :] = layer_v[layer_idx].to("cm/s").m
        p[s:e, :] = layer_pressure[layer_idx].to("barye").m

    # Assign ghost layer values
    for i in [0, -1]:
        rho[i, :] = layer_density[i].to("g/cc").m
        u[i, :] = layer_u[i].to("cm/s").m
        v[i, :] = layer_v[i].to("cm/s").m
        p[i, :] = layer_pressure[i].to("barye").m

    # cell spacing
    dy = (np.diff(y_2d[0, :]) / 2.0)[0]
    dx = (np.diff(x_2d[:, 0]) / 2.0)[0]

    # cell center locations
    xc = x_2d[:-1, :-1] + dx
    yc = y_2d[:-1, :-1] + dy

    return {
        "x": x_2d * ureg("cm"),
        "y": y_2d * ureg("cm"),
        "rho": rho * ureg("g/cc"),
        "u": u * ureg("cm/s"),
        "v": v * ureg("cm/s"),
        "p": p * ureg("barye"),
        "xc": xc * ureg("cm"),
        "yc": yc * ureg("cm"),
        "n_ghost_layers": n_ghost_layers,
    }


def make_1d_in_x_uniform_grid(n_cells, limits=(0, 1), input_file="input.ini"):
    """Generate a uniform grid 1d grid in x. This will output a dictionary
    that contains the appropriate arrays, which include the ghost
    cell layer.

    Parameters
    ----------
    n_cells : tuple
        Number of non-ghost cells
    limits : tuple
        Extent of the domain (min,max)

    Returns
    -------
    dictionary
        A dictionary that contains the conserved variables (rho, u velocity, v
        velocity, p), grid points, and the cell center (xc, yc) points
    """

    n_ghost_layers = get_n_ghost_layers_required(input_file)
    dx = float(limits[1] - limits[0]) / float(n_cells)
    x = np.linspace(
        start=limits[0] - n_ghost_layers * dx,
        stop=limits[1] + n_ghost_layers * dx,
        num=(n_cells + 1) + (n_ghost_layers * 2),
        dtype=np.float64,
    )

    y = (
        np.arange(-1 * n_ghost_layers, n_ghost_layers + 2, dtype=np.float64) * dx
        - dx / 2.0
    )
    xc = np.zeros(x.shape[0] - 1, dtype=np.float64)
    yc = np.zeros(y.shape[0] - 1, dtype=np.float64)

    # 2d versions
    y_2d, x_2d = np.meshgrid(y, x)  # nodes

    # cell-centered arrays
    cell_shape = (x_2d.shape[0] - 1, x_2d.shape[1] - 1)
    rho = np.ones(cell_shape)
    u = np.ones(cell_shape)
    v = np.ones(cell_shape)
    p = np.ones(cell_shape)

    # cell center locations
    xc = x_2d[:-1, :-1] + dx / 2.0
    yc = y_2d[:-1, :-1] + dx / 2.0

    return {
        "x": x_2d * ureg("cm"),
        "y": y_2d * ureg("cm"),
        "rho": rho * ureg("g/cc"),
        "u": u * ureg("cm/s"),
        "v": v * ureg("cm/s"),
        "p": p * ureg("barye"),
        "xc": xc * ureg("cm"),
        "yc": yc * ureg("cm"),
        "n_ghost_layers": n_ghost_layers,
    }


def write_initial_hdf5(filename, initial_condition_dict):
    """ Write the initial conditions to an hdf5 file.

    Parameters
    ----------
    filename : str
        Name of the grid file
    initial_condition_dict : dictionary
        Dictionary created by the `make_uniform_grid` method. Must
        contain the following keys ['x', 'y', 'rho', 'u', 'v', 'p']
    """

    if not filename.endswith(".h5") or not filename.endswith(".hdf5"):
        filename += ".h5"

    print("Writing to: ", filename)
    with h5py.File(filename, mode="w") as h5:

        data = initial_condition_dict["n_ghost_layers"]
        h5.create_dataset("/n_ghost_layers", data=data)

        data = initial_condition_dict["x"].to("cm").m
        dset = h5.create_dataset(
            "/x", data=data.astype(np.float64).T, compression="gzip", compression_opts=9
        )
        dset.attrs["units"] = "cm"

        data = initial_condition_dict["y"].to("cm").m
        dset = h5.create_dataset(
            "/y", data=data.astype(np.float64).T, compression="gzip", compression_opts=9
        )
        dset.attrs["units"] = "cm"

        data = initial_condition_dict["rho"].to("g/cc").m
        dset = h5.create_dataset(
            "/density",
            data=data.astype(np.float64).T,
            compression="gzip",
            compression_opts=9,
        )
        dset.attrs["units"] = "g/cc"

        data = initial_condition_dict["u"].to("cm/s").m
        dset = h5.create_dataset(
            "/x_velocity",
            data=data.astype(np.float64).T,
            compression="gzip",
            compression_opts=9,
        )
        dset.attrs["units"] = "cm/s"

        data = initial_condition_dict["v"].to("cm/s").m
        dset = h5.create_dataset(
            "/y_velocity",
            data=data.astype(np.float64).T,
            compression="gzip",
            compression_opts=9,
        )
        dset.attrs["units"] = "cm/s"

        data = initial_condition_dict["p"].to("barye").m
        dset = h5.create_dataset(
            "/pressure",
            data=data.astype(np.float64).T,
            compression="gzip",
            compression_opts=9,
        )
        dset.attrs["units"] = "barye"

        h5.close()
