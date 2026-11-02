#
# Copyright (c) 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# PROPRIETARY/CONFIDENTIAL
# Use is subject to license terms.
#

import argparse
import sys
import re
import pandas as pd
import numpy as np
import plotly.graph_objs as go
import plotly.express as px
from plotly.subplots import make_subplots


def print_summary(data):
    """
    Print the summary of the data
    """
    print("+-------------------------------------------+")
    print("|                    Summary                |")
    print("+-------------------------------------------+")
    mean_score = data.mean()
    mean_df = pd.DataFrame(mean_score)
    for col in mean_df.columns:
        mean_df[col] = mean_df[col].map('{:.2f}'.format)
    mean_df = mean_df[1:]
    print(mean_df)


def parse_data(file_path):
    """
    Parse the data file into a pandas dataframe
    :file_path: path to the data file
    :return: pandas dataframe of the data
    """

    timestamp_key = "time"
    timestamp_regex = r"(?:FL|SY),name=time;SY,value=([\d.]+);SY"
    data_regex = r"(?:FL|SY),name=([^;A-Z]+);SY,value=([\d.]+);(?:FL|SY)"
    with open(file_path, "r") as f:
        content = f.read()
        timestamps = re.findall(timestamp_regex, content)
        data_items = re.findall(data_regex, content)

    records = []
    i = 0
    for t in timestamps:
        record = {timestamp_key: int(t)}
        while i < len(data_items):
            key = data_items[i][0]
            value = float(data_items[i][1])
            i += 1
            if key == timestamp_key:
                break

            record[key] = value
        records.append(record)

    df = pd.DataFrame(records)
    return df


def plot_data(df, data_cpu):
    """
    Plot the time series data
    Args:
        df: pandas dataframe
        data_cpu: pandas dataframe
    Returns:
        None
    """

    df['cpu'] = data_cpu['cpu']
    i = 0
    fig = make_subplots(rows=df.shape[1] + 1, cols=1, shared_xaxes=True, subplot_titles="<b>" + df.columns[1:] + "</b>",
                        vertical_spacing=0.01)
    for i, col in enumerate(df.columns[1:(len(df.columns) - 1)], start=1):
        trace = go.Scatter(x=df["time"], y=df[col], mode="lines", name=col, legendgroup='1')
        fig.add_trace(trace, row=i, col=1)
        # fig.update_xaxes(title_text='time')

    for j, col in enumerate(data_cpu.iloc[:, :-1], start=1):
        fig.add_trace(go.Scatter(x=data_cpu['time'],
                                 y=data_cpu[col],
                                 mode='lines',
                                 name=col,
                                 legendgroup='2'),
                      row=i + 1, col=1)

    fig.update_layout(
        title="<b>Time Series Data</b>", autosize=True, legend_tracegroupgap=180, height=1200 * (df.shape[1] - 1),
        width=1600, plot_bgcolor='mintcream',
        legend_title="Legend Title",
        xaxis=dict(title='time in ms', showline=True, showgrid=True, showticklabels=True, linecolor='rgb(204,204,204)',
                   linewidth=4, ticks='outside', tickfont=dict(family='Arial', size=14, color='rgb(82,82,82)', ), ),
        yaxis=dict(showline=True, showgrid=True, showticklabels=True, linecolor='rgb(204,204,204)',
                   linewidth=4, ticks='outside', tickfont=dict(family='Arial', size=14, color='rgb(82,82,82)', ), ),
        margin=dict(autoexpand=False, l=100, r=20, t=110, ), )

    fig.show()
    fig.write_html("metrics_report.html")


def process_metrics_file(input_file, output_file):
    """
    Process the metrics file
    Args:
        input_file: input metrics file
        output_file: output metrics file
    Returns:
        None
    """

    # Parse the data file into a pandas dataframe
    data = parse_data(input_file)
    dtime = data[data.columns[pd.Series(data.columns).str.contains('time')]]
    dtime = dtime.copy()
    for col in dtime.columns:
        dtime[col] = dtime[col] - dtime[col].iloc[0]

    data['time'] = dtime

    # Write the metrics to CSV file
    data.to_csv(output_file)

    # write calculated average summary to CSV file
    df_avg = data.describe()
    df_avg.to_csv(f"avg_{output_file}")

    # Print the summary of the data
    print_summary(data)

    # Plot the time series data graph
    data_cpu = data[data.columns[pd.Series(data.columns).str.startswith('cpu')]]
    data_cpu = data_cpu.copy()
    data_cpu['time'] = dtime
    data = data.drop(data[data.columns[pd.Series(data.columns).str.startswith('cpu')]], axis=1)
    plot_data(data, data_cpu)


def plot_multiple_metrics(input_file, input_metrics):
    """
    Process to filter the input metrics data, generate a line plot for the
    selected metrics and saved the plot as a HTML file.
    Args:
        input_file: input metrics file
        input_metrics: filter metrics string
    Returns:
        None
    """
    data = parse_data(input_file)
    data_mem = data[data.columns[pd.Series(data.columns).str.startswith(input_metrics)]]
    dtime = data[data.columns[pd.Series(data.columns).str.contains('time')]]
    dtime = dtime.copy()
    for col in dtime.columns:
        dtime[col] = dtime[col] - dtime[col].iloc[0]
    data_mem['time'] = dtime
    print_summary(data_mem)
    fig1 = px.line(data_mem, x='time1', y=data_mem.columns)
    fig1.update_layout(xaxis=dict(title='time in ms', zeroline=False),
                       boxmode='group')
    fig1.show()
    fig1.write_html(f"{input_metrics}_metrics_report.html")


def plot_rollingaverage_metrics(input_file, input_metrics, output_file):
    """
    Process to generate a rolling average line plot for the selected metrics
    and saved the plot as a HTML file.
    Args:
        input_file: input metrics file
        input_metrics: filter metrics string
        output_file: output file name to save data into cvs format.
    Returns:
        None
    """
    data = parse_data(input_file)
    data_mem = data[data.columns[pd.Series(data.columns).str.startswith(input_metrics)]]
    data_mem['MA10'] = data_mem.rolling(10).mean()
    dtime = data[data.columns[pd.Series(data.columns).str.contains('time')]]
    dtime = dtime.copy()
    for col in dtime.columns:
        dtime[col] = dtime[col] - dtime[col].iloc[0]
    data_mem['time'] = dtime
    data_mem.to_csv(output_file)

    # write calculated average summary to CSV file
    df_avg = data_mem.describe()
    df_avg.to_csv(f"avg_{output_file}")
    print_summary(data_mem)
    fig1 = px.line(data_mem,
                   x='time',
                   y=data_mem.columns)
    fig1.update_layout(xaxis=dict(title='time in ms', zeroline=False),
                       boxmode='group')
    fig1.show()
    fig1.write_html(f"{input_metrics}_metrics_report.html")


def plot_group_of_metrics(input_file, input_metrics, output_file):
    """
    Process to generate a line plot for all the metrics that contain
    input_metrics string and saved the plot as a HTML file.
    Args:
        input_file: input metrics file
        input_metrics: filter metrics string
        output_file: output file name to save data into cvs format.
    Returns:
        None
    """
    data = parse_data(input_file)
    data_mem = data[data.columns[pd.Series(data.columns).str.contains(input_metrics)]]
    dtime = data[data.columns[pd.Series(data.columns).str.contains('time')]]
    dtime = dtime.copy()
    for col in dtime.columns:
        dtime[col] = dtime[col] - dtime[col].iloc[0]
    data_mem['time'] = dtime
    data_mem.to_csv(output_file)
    # write calculated average summary to CSV file
    df_avg = data_mem.describe()
    df_avg.to_csv(f"avg_{output_file}")

    fig1 = px.line(data_mem,
                   x='time',
                   y=data_mem.columns)
    print_summary(data_mem)
    fig1.update_layout(xaxis=dict(title='time in ms', zeroline=False),
                       boxmode='group')
    fig1.show()
    fig1.write_html(f"{input_metrics}_metrics_report.html")

def pick_nth_index_elements(df, n):
    """
    Pick up multiple of nth index elements from each column of a DataFrame.
    Args:
        df (pandas.DataFrame): Input DataFrame.
        n (int): Index to pick up elements from each column.
    Returns:
        pandas.DataFrame: New DataFrame with multiple of nth index elements.
    """
    # Create an empty DataFrame with the same columns as the input DataFrame
    new_df = pd.DataFrame(columns=df.columns)

    # Iterate over each column in the DataFrame
    for col in df.columns:
        # Pick up multiple of nth index elements for the current column
        selected_elements = df[col].iloc[::n]

        # Append the selected elements to the new DataFrame
        new_df[col] = selected_elements

    return new_df

def count_elements_to_cross_threshold(df, column_name, threshold=1000):
    """
    Count the number of elements in a DataFrame column required when
    their cumulative sum crosses a given threshold.
    Args:
        column (pandas.Series): The DataFrame column to analyze.
        threshold (int or float, optional): The threshold value. Default is 1000.
    Returns:
        int: The number of elements required to cross the threshold.
    """
    column_values = df[column_name].tolist()
    cumulative_sum = 0
    count = 0

    for value in column_values:
        cumulative_sum += value
        count += 1

        if cumulative_sum >= threshold:
            break

    return count

def plot_memory_bw_metrics(input_file, input_metrics, output_file):
    """
    This function reads a data file specified by input_file, extracts the columns
    that start with the input_metrics string, and creates a line plot for these
    columns using Plotly Express. The plots are displayed and saved as an HTML file.
    Args:
        input_file: input metrics file
        input_metrics: A string to identify memory BW metrics to be plotted.
        output_file: output file name to save data into cvs format.
    Returns:
        None
    """
    data = parse_data(input_file)
    data_mem = data[data.columns[pd.Series(data.columns).str.contains(input_metrics)]]
    dtime =  data[data.columns[pd.Series(data.columns).str.contains('time')]]
    dtime = dtime.copy()
    for col in dtime.columns:
        dtime[col] = dtime[col] - dtime[col].iloc[0]

    # Add the time columns to the data_mem DataFrame
    data_mem['time'] = dtime
    threshold_count = count_elements_to_cross_threshold(dtime, 'time')
    df_rol = pd.DataFrame()

    # Create a new column with the rolling sum of groups of 5 elements
    for col in data_mem.columns[data_mem.columns != 'time']:
        new_col = []
        for i in range(len(data_mem)):
            if i >= threshold_count:
                start = i - threshold_count
            else:
                start = 0
            new_col.append(sum(data_mem[col][start:i+1]))

        # Create a new DataFrame with the new column
        df_rol[col] = new_col

    df_rol['time'] = dtime
    df_bw = pick_nth_index_elements(df_rol, threshold_count + 1)
#    print(df_bw)
    df_bw.to_csv(output_file)

    fig1 = px.line(
        df_bw
        ,x = 'time'
        ,y = df_bw.columns
    )
    print_summary(df_bw)
    fig1.update_layout(
    xaxis=dict(title='time in ms', zeroline=False),
    boxmode='group')
    fig1.show()

if __name__ == "__main__":

    # Parse command line arguments.
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', action='store', dest='metrics_file', help='Metrics file name')
    parser.add_argument('-o', action='store', dest='output_file', help='CSV file name')
    parser.add_argument('-r', action='store', dest='rolling_avg', \
                        help='select one from the list [ina_nna_mw, ina_core_mw, ina_ddr_mw, \
                        ina_corea_mw, ina_coreb_mw]')
    parser.add_argument('-g', action='store', dest='metrics_group', \
                        help='select one from the list [cpu, memory, ina, wr_write_bytes, \
                        rd_read_bytes, p_read_bytes, p_write_bytes, p_rw_bytes]')
    parser.add_argument('-m', action='store', dest='metrics_mb', \
                        help='supported argument - [bytes_cycles]')
    args = parser.parse_args()
    if len(sys.argv) == 1 or args.metrics_file is None:
        parser.print_help(sys.stderr)
        sys.exit(1)

    if args.rolling_avg is not None:
        plot_rollingaverage_metrics(args.metrics_file, args.rolling_avg, args.output_file)
    elif args.metrics_group is not None:
        plot_group_of_metrics(args.metrics_file, args.metrics_group, args.output_file)
    elif args.metrics_mb is not None:
        plot_memory_bw_metrics(args.metrics_file, args.metrics_mb, args.output_file)
    else:
        process_metrics_file(args.metrics_file, args.output_file)