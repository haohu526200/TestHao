function [D,d_nBlock,block_fname] = read_data(con,block_num_p,info,)
% I need to add some help text in every function I write.
% This makes life much easier for everyone. :-)
pnet(con,'setreadtimeout',0);

block_fname = 'tmp_block.bin';
% read data block

D = struct('nBlock',[],'nPoints',[],'nMarkers',[],'Data',[],'Markers',[]);
D.Markers = struct('nSize',[],'nPosition',[],'nPoints',[], ...
    'nChannel',[],'sTypeDesc',[],'sStim',[]);

D.nBlock =  pnet(con,'read',1,'uint32','intel');                                       % 32 bits = 4 bytes / Block Number

%Check if any datapack were lost in the transfer
d_nBlock = D.nBlock-block_num_p ;
if d_nBlock>1 & block_num_p~=-1
    fprintf('\t%1.0f block(s) missed since block #%1.0f.\n',[d_nBlock-1,block_num_p]);
elseif block_num_p==-1
    d_nBlock == 1;
end

% Read rest of block only if it's new.
D.nPoints = pnet(con,'read',1,'uint32','intel');                                        % 32 bits = 4 bytes / Number of points
D.nMarkers = pnet(con,'read',1,'uint32','intel');                                       % 32 bits = 4 bytes / Number of markers

%With pnet it is better to read a lot of small parts than a big number array

%% Vitesse super lente / pas de blocage
% toadd = ones(info.nChannels, D.nPoints);
% prevind=1;
% packet = 50;
% step=floor(info.nChannels*D.nPoints/packet);
% for ii= 1:step
%     temp = pnet(con,'read',packet,'int16','intel');                            % Nch*Npts* 16 bits = Nch*Npts*2 bytes / Data
%     toadd(prevind:prevind+length(temp)-1)=temp;
%     prevind=prevind+length(temp);
%     while prevind-(ii-1)*packet<packet
%         temp = pnet(con,'read',packet-(prevind-1-(ii-1)*packet),'int16','intel');
%         toadd(prevind:prevind+length(temp)-1)=temp;
%         prevind=prevind+length(temp);
%     end
% end
% if (info.nChannels*D.nPoints/50-step) ~= 0
%     temp = pnet(con,'read',info.nChannels*D.nPoints/50-step,'int16','intel');                            % Nch*Npts* 16 bits = Nch*Npts*2 bytes / Data
%     toadd(prevind:prevind+length(temp)-1)=temp;
%     prevind=prevind+length(temp);
%     while prevind<=info.nChannels*D.nPoints
%         temp = pnet(con,'read',info.nChannels*D.nPoints-(prevind-1),'int16','intel');
%         toadd(prevind:prevind+length(temp)-1)=temp;
%         prevind=prevind+length(temp);
%     end
% end
% D.Data = reshape(toadd,info.nChannels,D.nPoints)';

%% Sol1 (vitesse lente mais fonctionne)
if replay
    toadd = ones(1, info.nChannels, D.nPoints);
    prevind=1;

    for ii= 1:D.nPoints

        temp = pnet(con,'read',info.nChannels,'int16','intel');                            % Nch*Npts* 16 bits = Nch*Npts*2 bytes / Data
        toadd(prevind:prevind+length(temp)-1)=temp;
        prevind=prevind+length(temp);

        while prevind-(ii-1)*info.nChannels<info.nChannels
            temp = pnet(con,'read',info.nChannels-(prevind-1-(ii-1)*info.nChannels),'int16','intel');
            toadd(prevind:prevind+length(temp)-1)=temp;
            prevind=prevind+length(temp);
        end
    end

    D.Data = reshape(toadd,info.nChannels,D.nPoints)';
    %
    %% Sol 2 vitesse moyenne (still trop rapide)

    % toadd = ones(info.nChannels, D.nPoints);
    % prevind=1;
    %
    % for ii= 1:info.nChannels
    %
    %     temp = pnet(con,'read',D.nPoints,'int16','intel');                            % Nch*Npts* 16 bits = Nch*Npts*2 bytes / Data
    %     toadd(prevind:prevind+length(temp)-1)=temp;
    %     prevind=prevind+length(temp);
    %
    %     while prevind<=D.nPoints*ii
    %         temp = pnet(con,'read',ii*D.nPoints-prevind+1,'int16','intel');
    %         toadd(prevind:prevind+length(temp)-1)=temp;
    %         prevind=prevind+length(temp);
    %     end
    % end
    %
    % D.Data = reshape(toadd,info.nChannels,D.nPoints)';
    %
else
    %% Sol3 Vit max (bcp trop rapide)
    toadd = pnet(con,'read',info.nChannels*D.nPoints,'int16','intel');
    while length(toadd)<info.nChannels*D.nPoints
        pause(eps)
        add2 = pnet(con,'read',info.nChannels*D.nPoints-length(toadd),'int16','intel');
        toadd = [toadd add2];
    end
    D.Data = reshape(toadd,info.nChannels,D.nPoints)';
end

% This code has never been tested for marker acquisition but it should
% work. If it isn't, use the code in comment at the end of the file.

if D.nMarkers>0
    % Read marker structure
    for ii=1:D.nMarkers
        % Importation of Marker Data

        D.Markers(ii).nSize = pnet(con,'read', 1, 'uint32','intel');                    % 32 bits = 4 bytes / Marker(ii) Size
        D.Markers(ii).nPosition = pnet(con,'read', 1,'uint32','intel') + 1;             % 32 bits = 4 bytes / Marker(ii) Position
        % '+1' because index starts at 0 in C...
        D.Markers(ii).nPoints = pnet(con,'read', 1,'uint32','intel');                   % 32 bits = 4 bytes / Number of points covered by Marker(ii)
        D.Markers(ii).nChannel = pnet(con,'read', 1,'int32','intel');                   % 32 bits = 4 bytes / Channel associated with Marker(ii)
        key = pnet(con,'read', D.Markers(ii).nSize-16,'char','intel');                  % (Marker(ii)Size - 16) * 8 bits = Marker(ii)Size - 16 bytes
        % / Description of the marker.


        %             disp(['Message : ',char(key)])
        l_S = find(key==83) ; % Pickup the second 'S' of 'Stimulus S123 '
        % or from 'DeferCommentStart/DeferCommentEnd'
        if length(l_S)>1
            % If simple number from the port
            D.Markers(ii).sTypeDesc = char(key(l_S(2):(end-1)));
            % Keep only 'S123'
            D.Markers(ii).sStim = 1;
        else
            tmp = key(14:end) ; % Remove '~DeferComment'
            tmp(find(tmp==00))=32; % Change weird space into printable space
            D.Markers(ii).sTypeDesc = char(tmp); % Keep the rest
            D.Markers(ii).sStim = 0;
        end

    end

end

% Replace the Marker handling code by the following one if you do not care
% about markers.
%
% garbage = pnet(con,'read', hdr.nSize-header_size-8-info.nChannels*D.nPoints*2, 'char','intel');


% Old CP code
%
% % read data block
%
% block_fname = 'tmp_block.bin';
% ret = pnet(con,'readtofile',block_fname,hdr.nSize-header_size);
% D = struct('nBlock',[],'nPoints',[],'nMarkers',[],'Data',[],'Markers',[]);
% D.Markers = struct('nSize',[],'nPosition',[],'nPoints',[], ...
%                                 'nChannel',[],'sTypeDesc',[],'sStim',[]);
%
% fid = fopen(block_fname);
% D.nBlock  = fread(fid,1,'uint32') ;
% d_nBlock = D.nBlock-block_num_p ;
% if d_nBlock>1 & block_num_p~=-1
%     fprintf('\t%1.0f block(s) missed since block #%1.0f.\n',[d_nBlock-1,block_num_p]);
% elseif block_num_p==-1
%     d_nBlock == 1;
% end
%
% if d_nBlock>0
% % Read rest of block only if it's new.
% 	D.nPoints = fread(fid,1,'uint32');
% 	D.nMarkers = fread(fid,1,'uint32');
% 	D.Data = fread(fid,[info.nChannels D.nPoints],'short')';
%
% 	l_MarkerType = 0;
% 	if D.nMarkers>0
%         % Read marker structure
%         for ii=1:D.nMarkers
%             D.Markers(ii).nSize = fread(fid,1,'uint32');
%             D.Markers(ii).nPosition = fread(fid,1,'uint32')+1;
%                 % '+1' because index starts at 0 in C...
%             D.Markers(ii).nPoints = fread(fid,1,'uint32');
%             D.Markers(ii).nChannel = fread(fid,1,'long'); % type length : 4bytes
%             key = fread(fid,D.Markers(ii).nSize-16,'char')' ;
% %             disp(['Message : ',char(key)])
%             l_S = find(key==83) ; % Pickup the second 'S' of 'Stimulus S123 '
%                                   % or from 'DeferCommentStart/DeferCommentEnd'
%             if length(l_S)>1
%                 % If simple number from the port
%                 D.Markers(ii).sTypeDesc = char(key(l_S(2):(end-1)));
%                         % Keep only 'S123'
%                 D.Markers(ii).sStim = 1;
%             else
%                 tmp = key(14:end) ; % Remove '~DeferComment'
%                 tmp(find(tmp==00))=32; % Change weird space into printable space
%                 D.Markers(ii).sTypeDesc = char(tmp); % Keep the rest
%                 D.Markers(ii).sStim = 0;
%             end
%         end
% 	end
% 	if hdr.nSize~=ret+header_size
%         error('There was some problem reading the data block')
% 	end
% end
% fclose(fid);
% return
%
