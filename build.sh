#!/usr/bin/env bash

set -e
ROOT=`pwd`

if [[ "$TRAVIS_EVENT_TYPE" == 'cron' ]] || [[ `git --no-pager log -1 --oneline` == *'[cron debug]'* ]]; then
	REPO=`git config remote.origin.url`
	SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}

	chmod 600 deploy_key
	eval `ssh-agent -s`
	ssh-add deploy_key

	TODAY=`date -u +%F`

	git fetch --tags
	git submodule foreach 'git checkout master && git fetch origin master --tags && git pull'

	if [[ -n `git status -s` ]]; then
		git commit -am "Update to latest master on all for $TODAY"
	fi

	# Gather tags latest non-nightly tags for the main repo and FFmpeg submodule
	MAIN_LATEST_TAG=`git tag --sort=-taggerdate | grep -v "nightly*" | head -1`
	cd ffmpeg
	FFMPEG_LATEST_TAG=`git tag --sort=-taggerdate | head -1`
	cd ..

	# Tag the nightly release
	git tag -a "nightly-$TODAY" -m "Nightly build for $TODAY"

	# If the FFmpeg repo has a newer tag, create a tag for this repo
	if [ "$MAIN_LATEST_TAG" != "$FFMPEG_LATEST_TAG" ]; then
		git checkout -b "release/$FFMPEG_LATEST_TAG"
		git submodule foreach 'git checkout $(git tag --sort=-taggerdate | head -1)'
		MSG="Release for FFmpeg $FFMPEG_LATEST_TAG"$'\n'`git submodule foreach --quiet 'echo "$name: $(git describe --tags --abbrev=0)"'`
		git commit -am "${MSG[@]}"
		git tag -a "$FFMPEG_LATEST_TAG" -m "${MSG[@]}"
	fi

	# Push updated repo and tags
	git push "$SSH_REPO" master --tags

	exit 0;
fi

# Don't build master, since it will only contain the latest nightly commits.
if [ "$TRAVIS_BRANCH" == "master" ]; then
	echo "Skipping build for 'master' branch... Just keeping things up-to-date"
	exit 0;
fi

# libx265
echo "Building libx265"
cd "$ROOT/x265/build/linux"
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source
make
make install

# libvpx
echo "Building libvpx"
cd "$ROOT/libvpx"
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests
PATH="$HOME/bin:$PATH" make
make install
make clean

echo "Building FFmpeg"
cd "$ROOT/ffmpeg"
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
	--prefix="$HOME/ffmpeg_build" \
	--pkg-config-flags="--static" \
	--extra-cflags="-I$HOME/ffmpeg_build/include" \
	--extra-ldflags="-L$HOME/ffmpeg_build/lib" \
	--bindir="$HOME/bin" \
	--arch="x86_64" \
	--enable-gpl \
	--disable-runtime-cpudetect \
	--disable-ffplay \
	--disable-ffserver \
	--disable-doc \
	--disable-network \
	--disable-protocols \
	--enable-protocol=file \
	--enable-protocol=pipe \
	--enable-protocol=tee \
	--enable-libmp3lame \
	--enable-libvpx \
	--enable-libx264 \
	--enable-libx265 \
	--enable-libxvid
PATH="$HOME/bin:$PATH" make
make install
make distclean
hash -r

# Generate README.txt
echo "Generating README"
echo "
`figlet -f slant "FFmpeg"`

Build version: $TRAVIS_TAG
Build date: `date -u`

`$HOME/bin/ffmpeg -version`

This build of FFmpeg is licensed under the GPL. See the source code for details.
" > "$HOME/bin/README.txt"

tar -czvf "$TRAVIS_BUILD_DIR/ffmpeg-build-lambda.tar.gz" $HOME/bin/*
