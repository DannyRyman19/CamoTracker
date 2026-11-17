"""Runs the iOS repo's synth_grid.py with another random seed (its README:
"change random.seed first" for the validation set).
usage: run_synth_grid.py SYNTH_GRID_PY SEED TILES BACKDROPS OUT COUNT"""
import sys
path, seed = sys.argv[1], sys.argv[2]
src = open(path).read().replace('random.seed(11)', f'random.seed({seed})')
sys.argv = [path] + sys.argv[3:]
exec(compile(src, path, 'exec'), {'__file__': path, '__name__': '__main__'})
