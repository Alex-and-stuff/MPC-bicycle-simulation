clear;
close all;
clc;

% Simulation Parameters
STATES     = 4;                         % Number of states   x = [X,Y,Phi,v0]
CONTROLS   = 2;                         % Number of controls u = [vd,wd]
T_hrz      = 2;                       % Prediction time horizon (  sec)
F_stp      = 20;                        % Frequency of prediction ( 20Hz)
T_stp      = 1/F_stp;                   % Period of prediction    (0.05s)
N_hrz      = T_hrz*F_stp;               % N steps in one time horizon  (30 steps per sequence)


% Initial condition, Assume here that we don't take the steering angle into account for now??
X   = 150.91;                            % m
Y   = 126.71;                           % m 
Phi = -0.5;                             % rad
V0  = 2;                                % m/s
x0  = [X,Y,Phi,V0];                     % Initial state condition
vd_max = 4;
vd_min = 1.5;
wd_max = 1.5;
wd_min = -1.5;


n_gen      = 0;                         % N-th generation of perdiction
K          = 1000;                      % 1000 Monte Carlo rollouts 
U          = zeros(CONTROLS,N_hrz-1);   % The whole control sequence in 1 time horizon
U_pert     = zeros(CONTROLS,N_hrz-1);   % The whole control perturbation for a single rollout
U_all      = zeros(CONTROLS,N_hrz-1,K); % Store all control rollouts (with perturbation)
U_opt      = zeros(CONTROLS,N_hrz-1);   % The optimal control sequence in 1 time horizon
pert_u     = 0;                         % Mean of the added control perturbation
pert_stdev = 2;                         % Variance of the added control perturbation
lambda = 50;

% Simulation resoluton setup
dt    = 0.05;                          % Simulation resolution
t_end = 15;                             % Simulation time (15s)
N     = t_end/dt;                       % N iterations in the full simulation (N = 30000 iterations)

% Simulation Records
x_hrz = zeros(STATES,N_hrz,K);          % Record all simulated rollout states
x_log = zeros(STATES,N);                % Record state (x) data for every simulation iteration
u_log = zeros(CONTROLS,N);              % Record control (u) data for every simulation iteration
x_log(:,1) = x0;                        % Record the initial state 
S     = zeros(1,K);                     % Record cost of all rollouts
t_log = zeros(1,N);

for k = 1:N_hrz-1
U(:,k)=[2,0];
end

% Build obstacles
obstacle = [154 ,125.7 ,1;
            152 ,119   ,1];

% Build track
mid_fcn = [1.0000,   -1.33200,    82.62978;
           1.0000,    0.75640,  -240.86623;
           1.0000,   -1.36070,   -33.13473;
           1.0000,    0.47203,   -35.00739];
       
road_width = 2;
[outer_fcn,inner_fcn,mid_fcn,outer_intersec,inner_intersec,mid_intersec]= build_track(mid_fcn, road_width);

% Main MPPI Code
for curr_step = 1:N-1                                                   % Start simulation by stepping forward (1 to 30000-1)
    n_curr = ceil(curr_step*dt/T_stp);                                  % Find the current genertion (nearest max integer) 
    if n_gen < n_curr                                                   % Next prediction generation has arrived
        n_gen = n_gen+1;                                                % Update current generation of prediction
        U = [U(:,2:N_hrz-1), [0;0]];                                    % Shift forward the control sequence by one
%         disp(U(:,1))
        x0 = x_log(:,curr_step);                                        % Set current state as initial condition for prediction
        x_hrz = 0.*x_hrz;                                               % Reset x_hrz to 0
        S = 0.*S;                                                       % Reset all rollout costs to 0
        for kth_rollout = 1:K                                           % Iterate through all Monte Carlo rollouts
            U_pert = normrnd(pert_u, pert_stdev, [CONTROLS,N_hrz-1]);   % Generate control perturbation sequence 
            U_all(:,:,kth_rollout) = U + U_pert;                        % Store the perturbated control of the k-th rollout
            
            x_hrz(:,1,kth_rollout) = x0;                                % Set the initial state for all the rollouts
            for nth_step = 1:N_hrz-1                                    % Iterate through the time horizon to calcuale the total cost for each rollout
                U_all(:,nth_step,kth_rollout) = clamping_fcn(U_all(:,nth_step,kth_rollout),vd_max,vd_min,wd_max,wd_min);
                x_dot = BicycleModelMPPI(...                            % Generate x_dot with model
                        x_hrz(:,nth_step,kth_rollout), ...
                        U_all(:,nth_step,kth_rollout));
                x_hrz(:,nth_step+1,kth_rollout) = ...                   % Store new state from x_dot of every rollout
                        x_hrz(:,nth_step,kth_rollout) + x_dot*T_stp; 
                S(kth_rollout) = S(kth_rollout) + ...                     % Compute the cost for every rollout
                                 stateCost(x_hrz(:,nth_step,kth_rollout), ...
                                 x_dot,U_all(:,nth_step,kth_rollout),inner_fcn, ...
                                 outer_fcn, road_width,obstacle);
                
            end
            
        end
 
        rho = min(S);
        mmaaxx = max(S);
%         fprintf('%d %d.\n', rho, mmaaxx);
        eta = exp(-1/lambda*(S-rho));
        w = eta/sum(eta);
        
        U_opt = 0.*U_opt;
        for j = 1:K
            U_opt = U_opt + w(j)*U_all(:,:,j);
        end
        U = U_opt;
        
        
        %new
        
        
    end
%     disp(U_opt(:,1:10))
    u = U_opt(:,1);
    x_dot = BicycleModelMPPI(x_log(:,curr_step),u);                     % Generate x_dot with model
    x_log(:,curr_step+1) = x_log(:,curr_step)+x_dot*dt;                 % Store new state from x_dot
    u_log(:,curr_step) = u;                                             % Store control at step instance 
    t_log(1,curr_step) = curr_step;
    
    state = x_log(:,curr_step);
    control = u;
    % Create single figure
    h = figure(1);   
%     h.Position=[500 100 1000 800];
    
    % Clear the plot to elimanate old image
    clf;
    hold on;
    
%     pos1 = [0 inf 0 0.5];
%     h1 = subplot(2,2,1);
%     h1.Position = h1.Position + [0 0 0 0];
% %     h1.Position = [1 1 1 1]
%     scatter(1,1);
%     title('First Subplot')
%     
%     pos2 = [0 inf 0 0.5];
%     h2 = subplot(2,2,2);
% %     h2.Position = h2.Position + [0 0.05 0 0];
%     scatter(1,1);
%     title('Second Subplot')
%     
%     % Call function to draw the bicycle
%     subplot(2,2,[3,4]);
    draw_track(inner_intersec, outer_intersec, mid_intersec);
    draw_obstacle(obstacle);
    draw_rollouts(x_hrz,K,S);
    DrawBicycle(state, control);
    

%     axis equal;
%     axis([150-25 158+10 120-3 128]);
%     set(gcf,'Position',[state(1) state(2) 50 50],'Resize','off');
    axis([150-5 158 120-5 128]);
    
    % Draw GIF
    drawnow 
    filename = 'MPC_sim3.gif';
    
    % Capture the plot as an image 
    frame = getframe(h); 
    im = frame2im(frame); 
    [imind,cm] = rgb2ind(im,256); 
    % Write to the GIF File 
    if curr_step == 1 
        imwrite(imind,cm,filename,'gif', 'Loopcount',inf); 
    else 
        imwrite(imind,cm,filename,'gif','WriteMode','append'); 
    end 
    
    h2 = figure(2);
    hold on;
%     scatter(curr_step, u(1), 'b');
    plot(t_log(1:curr_step), u_log(1,1:curr_step), 'b');
    axis([0 inf 1.5 4]);
    
    h3 = figure(3);
    hold on;
%     scatter(curr_step, u(1), 'b');
    plot(t_log(1:curr_step), u_log(2,1:curr_step), 'r');
    axis([0 inf -1.2 1.2]);
    
%     if curr_step > dt
%     figure(2);
% %     t_log = 1:1:n_curr-1;
%     plot(t_log(1,1:n_curr-1), u_log(1,1:n_curr-1));
%     axis([1 inf 1 3]);
%     end
    
    
%     disp(curr_step);
%     disp(u);
end