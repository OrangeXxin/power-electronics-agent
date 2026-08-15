load_system('ee_lib');
all_blks = find_system('ee_lib','FollowLinks','on','LookUnderMasks','all','Type','block');
fprintf('==== ee_lib 中含 PWM/Pulse 的块 ====\n');
for k=1:numel(all_blks)
    nm = all_blks{k};
    if ~isempty(regexpi(nm,'pwm|pulse|carrier|comparator'))
        fprintf('  %s\n', nm);
    end
end
fprintf('--- total blocks: %d ---\n', numel(all_blks));