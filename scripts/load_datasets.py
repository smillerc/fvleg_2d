# -*- coding: utf-8 -*-
"""Read the .h5 files from a simulation into an xarray Dataset"""
import configparser
import os

import h5py
import numpy as np
import pint
import xarray as xr


ureg = pint.UnitRegistry()


def read_stepfile(file):
    """Read a single .hdf5 file

    Parameters
    ----------
    file : string
        Filename of the hdf5 file

    Returns
    -------
    Dict
        Dictionary of the data from within the hdf5 file
    """
    data = {}

    var_list = ["x", "density", "x_velocity", "y_velocity", "pressure", "sound_speed"]

    with h5py.File(file, "r") as h5:
        # Transpose to match the index convention within the code
        data["time"] = h5["/time"][()]
        data["time_units"] = h5["/time"].attrs["units"].decode("utf-8")
        for var in var_list:
            try:
                data[var] = h5[f"/{var}"][()].T
                data[var + "_units"] = h5[f"/{var}"].attrs["units"].decode("utf-8")
            except Exception:
                print(f"Unable to read {var}")
    return data


def generate_dataset(var_dict, unit_system="icf"):
    """Make an xarray dataset

    Parameters
    ----------
    var_dict : dict
        Dictionary that contains the following keys
        ['density', 'pressure', '(x_/y_)velocity', 'sound_speed', 'pulse']

    Returns
    -------
    xr.Dataset
        An xarray Dataset
    """

    if unit_system == "cgs":
        density_units = "g/cc"
        pressure_units = "barye"
        vel_units = "cm/s"
        time_units = "s"
        length_units = "cm"

    else:
        unit_system = "icf"
        density_units = "g/cc"
        pressure_units = "Mbar"
        vel_units = "um/ns"
        time_units = "ns"
        length_units = "um"

    time = var_dict["time"]
    sound_speed = var_dict["sound_speed"]
    pressure = var_dict["pressure"]
    density = var_dict["density"]

    # density.shape = (t, i, j)
    if len(density.shape) > 2 or (len(density.shape) == 3 and density.shape[2] > 3):
        is_2d = True
        is_1d = False
        x = var_dict["x"]
        y = var_dict["y"]
    else:  # 1D
        is_2d = False
        is_1d = True
        x = var_dict["x"]

    if is_1d:
        space_dims = ("time", "x")
        coords = {"time": time.to(time_units).m, "x": x.to(length_units).m}
    elif is_2d:
        space_dims = ("time", "x", "y")
        coords = {
            "time": time.to(time_units).m,
            "x": x.to(length_units).m,
            "y": y.to(length_units).m,
        }
    else:
        raise Exception("The dimensionality should be 1D or 2D...")

    ds = xr.Dataset(
        data_vars={
            "density": xr.Variable(
                space_dims, density.to(density_units).m, attrs={"units": density_units}
            ),
            "sound_speed": xr.Variable(
                space_dims, sound_speed.to(vel_units).m, attrs={"units": vel_units}
            ),
            "pressure": xr.Variable(
                space_dims,
                pressure.to(pressure_units).m,
                attrs={"units": pressure_units},
            ),
        },
        coords=coords,
        attrs={"name": var_dict["name"], "time_units": time_units},
    )

    if is_1d:
        velocity = var_dict["velocity"]
        ds["velocity"] = xr.Variable(
            space_dims, velocity.to(vel_units).m, attrs={"units": vel_units}
        )
    elif is_2d:
        x_velocity = var_dict["x_velocity"]
        ds["x_velocity"] = xr.Variable(
            space_dims, x_velocity.to(vel_units).m, attrs={"units": vel_units}
        )
        y_velocity = var_dict["y_velocity"]
        ds["y_velocity"] = xr.Variable(
            space_dims, y_velocity.to(vel_units).m, attrs={"units": vel_units}
        )

    # Add a pulse if one exists, i.e. boundary pressure input
    if "pulse" in var_dict.keys():
        pulse_units = str(var_dict["pulse"].units)
        pulse = var_dict["pulse"]
        ds["pulse"] = xr.Variable(
            ("time"), pulse.to(pulse_units).m, attrs={"units": pulse_units}
        )

    return ds


def load_1d_dataset(folder, units="cgs"):
    """Load a 1D CATO dataset into an xarray Dataset container

    Parameters
    ----------
    folder : str
        Folder containing the step files
    units : str, optional
        Desired unit system to convert the quantities to, by default 'cgs'. 'icf' will use
        conventions typical in the ICF community, e.g. [g/cc, um, km/s, eV]

    Returns
    -------
    xr.Dataset
        An xarray Dataset containing the time-varying data
    """

    if units != "cgs" and units != "icf":
        raise Exception("Unsupported units not in the set = {cgs, icf}")

    step_files = sorted(
        [
            os.path.join(folder, f)
            for f in os.listdir(folder)
            if f.endswith(".h5") and f.startswith("step")
        ]
    )
    data = read_stepfile(step_files[0])
    data_dim_x = data["density"].shape[0]
    data_dim_t = len(step_files)

    data = {
        "name": str(folder).split("/")[-1],
        "x": np.zeros((data_dim_t, data_dim_x + 1)),
        "time": np.zeros(data_dim_t),
        "density": np.zeros((data_dim_t, data_dim_x)),
        "pressure": np.zeros((data_dim_t, data_dim_x)),
        "sound_speed": np.zeros((data_dim_t, data_dim_x)),
        "velocity": np.zeros((data_dim_t, data_dim_x)),
        # "y_velocity": np.zeros((data_dim_t, data_dim_x)),
    }

    for t, f in enumerate(step_files):
        single_step_data = read_stepfile(f)
        data["x"][t, :] = single_step_data["x"][:, 0]
        data["time"][t] = single_step_data["time"]
        data["velocity"][t, :] = single_step_data["x_velocity"][:, 0]
        # data["y_velocity"][t, :] = single_step_data["y_velocity"][:, 0]
        data["density"][t, :] = single_step_data["density"][:, 0]
        data["sound_speed"][t, :] = single_step_data["sound_speed"][:, 0]
        data["pressure"][t, :] = single_step_data["pressure"][:, 0]

    data["density"] = data["density"] * ureg(single_step_data["density_units"])
    data["pressure"] = data["pressure"] * ureg(single_step_data["pressure_units"])
    data["sound_speed"] = data["sound_speed"] * ureg(
        single_step_data["sound_speed_units"]
    )
    data["velocity"] = data["velocity"] * ureg(single_step_data["x_velocity_units"])
    # data["y_velocity"] = data["y_velocity"] * ureg(single_step_data["y_velocity_units"])
    data["time"] = data["time"] * ureg(single_step_data["time_units"])
    data["x"] = np.cumsum(np.diff(data["x"][0])) * ureg(single_step_data["x_units"])

    # Read the input.ini
    config = configparser.ConfigParser()
    config.read(os.path.join(folder, "input.ini"))

    pressure_pulse = False
    if config["boundary_conditions"]["plus_x"].strip("'") == "pressure_input":
        pressure_pulse = True

        pulse_file = os.path.join(
            folder, config["boundary_conditions"]["bc_pressure_input_file"].strip("'")
        )

        # Read the pulse input
        pulse = np.loadtxt(pulse_file, skiprows=1)
        pulse_t = pulse[:, 0] * ureg("s")
        pulse_p = pulse[:, 1] * ureg("barye")

        # Interpolate the pulse to the dataset time
        data["pulse"] = np.interp(
            data["time"].to("s").m, pulse_t.to("s").m, pulse_p.to("barye").m
        ) * ureg("barye")

    ds = generate_dataset(data, unit_system=units)

    return ds
